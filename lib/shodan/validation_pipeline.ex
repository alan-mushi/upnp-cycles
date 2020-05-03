defmodule Shodan.ValidationPipeline do
  require Logger
  require Host
  require ProcessorFragment

  import BroadwayHelper

  use Broadway

  alias Shodan.Repo
  alias Broadway.Message

  @moduledoc ~S"""
  `ValidationPipeline` checks if a host has the AddPortMapping Upnp action available.

  Roughly, the code logic is as follows:

    Host
    |> Ecto save host
    |> Ensure UPNP port
    |> Extract Location Header
    |> Fetch UPNP Device desc + validate xml
    |> Fetch UPNP WANIPConn1 des + validate xml
    |> Ecto save all results

  The `Host` is augmented with the `ProcessorFragment` containing intermediary
  results for ease of debugging and tracking. The `Broadway.Message` saved
  contains error messages showing were it went wrong (if it did).

  Finally, hosts that successfully went through the pipeline are sent to
  `OpenPortsPipeline` to enumerate port mappings.

  # Failure reasons and format in status messages

   * Step 0: `{:not_upnp_port, port_number}`
   * Step 1: `{:location_not_suitable, URI}`
   * Step 2: `{:fetch_failed, {reason, URI}} and {:invalid_device_description, desc}`
   * Step 3: `{:no_wanipconn1_service_found, [Upnp.Service]}`
   * Step 4: `{:fetch_failed, {reason, URI}} and {:invalid_service_description, desc}`
   * Step 5: `{:addPortMapping_action_not_found, [Upnp.Action]}`
   * Otherwise: `{failed_unknown_reason: Broadway.Message}`

  # Implementation notes:

  The code logic needs to save intermediary results to fill the message's data
  with a complete `ProcessorFragment` struct, this will allow to replay and
  debug much more easily. Doing so is problematic as Broadway does not
  currently support multiple processors, so we have to work-around it by being
  able to mark the message as failed (with a useful reason) and not process the
  message further.

  This could be achieved with a lot of russian-doll `if` but it felt awkward.
  Instead, functions processing states are wrapped in `run_if_status_is_ok`,
  skipping processing of the message if it's already failed or executing the
  step if all is well. It's more intelligible than a succession of `if` but
  it's a bit wordy...

  # Improvements to be made (TODO maybe)
  [X] Save the output in a database
  [ ] Integrate `telemetry`
  [ ] Integrate `spandex`
  """

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: ValidationPipeline,
      producer: [
        module: {Shodan.ShimProducer, []},
        transformer: {BroadwayHelper, :transform, []},
      ],
      processors: [
        default: [concurrency: 150],
      ],
      batchers: [
        ecto: [concurrency: 1, batch_size: 10],
      ]
    )
  end

  # Step 1
  defp extract_location_header(%Message{data: {%Host{} = host, _pf}} = m, _opts, default) do
    case Host.location_to_external_ip(host) do
      [location | []] -> {m, location |> URI.parse}
      locations -> {Message.failed(m, {:location_not_suitable, locations}), default}
    end
  end

  # Step 2
  defp get_upnp_device_description(%Message{} = m, location, default) do
    case Shodan.IgdProber.get(location) do
      {:ok, res} -> {m, res.body}
      {:error, reason} -> {Message.failed(m, {:fetch_failed, {reason, location}}), default}
    end
  end

  defp validate_upnp_device_description(%Message{} = m, fetch_res, default) do
    case Shodan.IgdProber.is_valid_device?(fetch_res) do
      true -> {m, fetch_res}
      false -> {Message.failed(m, {:invalid_device_description, fetch_res.body}), default}
    end
  end

  # Step 3
  defp get_upnp_services(%Message{} = m, device_description, default) do
    services = Shodan.IgdProber.parse_xml_response(device_description)
               |> Shodan.IgdProber.extract_all_service()

    case Enum.filter(services, &Shodan.IgdProber.is_WANIPConn1?/1) do
      [wanipconn1 | []] -> {m, {services, wanipconn1}}
      other -> {Message.failed(m, {:no_wanipconn1_service_found, other}), default}
    end
  end

  # Step 4
  defp get_upnp_service_description(%Message{} = m, {%Upnp.Service{} = wanipconn1, location}, default) do
    service_description_location = Upnp.to_full_uri(wanipconn1, location)
                                   |> Map.get(:SCPDURL, nil)
                                   |> URI.parse()

    case Shodan.IgdProber.get(service_description_location) do
      {:ok, res} -> {m, res.body}
      {:error, reason} -> {Message.failed(m, {:fetch_failed, {reason, service_description_location}}), default}
    end
  end

  defp validate_upnp_service_description(%Message{} = m, service_description, default) do
    case Shodan.IgdProber.is_valid_service?(service_description) do
      true -> {m, service_description}
      false -> {Message.failed(m, {:invalid_service_description, service_description}), default}
    end
  end

  # Step 5
  defp extract_actions(%Message{} = m, service_description, default) do
    actions = service_description
              |> Shodan.IgdProber.parse_xml_response()
              |> Shodan.IgdProber.extract_all_action()

    case Enum.filter(actions, &Shodan.IgdProber.is_AddPortMapping?/1) do
      [addPortMapping_action | []] -> {m, [addPortMapping_action | actions]}
      other -> {Message.failed(m, {:addPortMapping_action_not_found, other}), default}
    end
  end

  defp process_message(%Message{data: {%Host{} = host, pf}} = m) do
    # 0. Insert (or load host) in the database
    host = Repo.get_or_insert_host!(host)
    m = %Message{m | data: {host, pf}}

    # 1. Extract Location header from data
    {%Message{} = m, location} = run_if_status_is_ok(m, &extract_location_header/3, [])

    # 2. Fetch and verify UPNP devices description
    {m, res} = run_if_status_is_ok(m, &get_upnp_device_description/3, location)
    {m, device_description} = run_if_status_is_ok(m, &validate_upnp_device_description/3, res)

    # 3. Extract, fetch and verify UPNP services matching WANIPConn1
    {m, {services, wanipconn1_service}} = run_if_status_is_ok(m, &get_upnp_services/3, device_description, {nil, nil})

    # 4. Fetch the service description having WANIPConn1 as an action
    {m, res} = run_if_status_is_ok(m, &get_upnp_service_description/3, {wanipconn1_service, location})
    {m, service_description} = run_if_status_is_ok(m, &validate_upnp_service_description/3, res)

    # 5. Extract actions
    {m, [addPortMapping_action | actions]} = run_if_status_is_ok(m, &extract_actions/3, service_description, [nil])

    Logger.debug("#{host.ip} made it to the end of processing with a status of #{inspect m.status}")

    # Saving it all in our message

    pf_data = %{
      upnp_device_description_location: location,
      upnp_device_description: device_description,
      upnp_services: services,
      upnp_service_description: service_description,
      upnp_WANIPConn1_service_description: wanipconn1_service,
      upnp_actions: actions,
      upnp_addPortMapping_action: addPortMapping_action,
    }
    res_pf = Map.put(pf, :data, pf_data)

    %Message{m | data: {host, res_pf}}
    |> Message.put_batcher(:ecto)
  end

  @impl true
  def handle_message(_processor, %Message{data: {%Host{port: port} = host, nil}} = m, _context) do
    pf = ProcessorFragment.bootstrap(__MODULE__)
    m = %Message{m | data: {host, pf}}

    # Step 0, filter upnp ports
    case port do
      1900 -> process_message(m)
      _ -> Message.failed(m, {:not_upnp_port, port})
    end
  end

  def store_result!(%Message{} = m) do
    {host, pf} = m.data

    status = BroadwayHelper.extract_status(m)

    res_pf = ProcessorFragment.changeset(%ProcessorFragment{}, Map.put(pf, :status, status))
             |> Ecto.Changeset.put_assoc(:host, host)
             |> Repo.insert!()
             |> Repo.preload(:host)

    res_host = Repo.preload(host, [:processors])

    %Message{m | data: {res_host, res_pf}}
  end

  @impl true
  def handle_failed(messages, _context) do
    Enum.map(messages, &store_result!(&1))
  end

  @impl true
  def handle_batch(:ecto, messages, _batch_info, _context) do
    for m <- messages do
      store_result!(m)

      # Send to OpenPortsPipeline successful candidates
      {host, _} = m.data
      BroadwayHelper.transform_and_push_message(OpenPortsPipeline, host)
    end
  end
end

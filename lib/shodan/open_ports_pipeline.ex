defmodule Shodan.OpenPortsPipeline do
  require Logger
  require Host
  require ProcessorFragment

  import BroadwayHelper

  use Broadway

  alias Shodan.Repo
  alias Broadway.Message

  @moduledoc ~S"""
  `OpenPortsPipeline` fetches the port mappings for hosts having successfully
  passed the `ValidationPipeline`.

  Code logic:

    Host
    |> Ecto get host (check not one of our IPs)
    |> Ecto get latest ProcessorFragment set by ValidationPipeline
    |> List mapped ports
    |> Ecto save all results

  Ecto is used quite heavily so we can go through the pipeline without having
  to dig-up ourselves a lot of info. It's easier for debugging and for looking
  at port mapping over time.

  There is no loop checks. It's not reasonable in a "normal" setup and a bit
  painful to check for in a parallel setup (like this one).

  # Failure reason and format in saved status messages

    * Step 1: `{:host_does_not_exist, [ip: ip, port: port]}`, `{:one_of_our_ips, nil}`
    * Step 2: `{:no_processor_fragments, nil}`
    * Step 3: No error message
    * Otherwise: `{failed_unknown_reason: Broadway.Message}`

  # Improvements to be made (TODO maybe)
  [X] Save the output in a database
  [ ] Integrate `telemetry`
  [ ] Integrate `spandex`
  """

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: OpenPortsPipeline,
      producer: [
        module: {Shodan.ShimProducer, []},
        transformer: {BroadwayHelper, :transform, []},
      ],
      processors: [
        default: [concurrency: 20, max_demand: 1],
      ],
      batchers: [
        ecto: [concurrency: 1, batch_size: 10],
      ]
    )
  end

  # Step 1
  defp get_host(%Message{data: {%Host{ip: ip, port: port}, _}} = m, _opt, default) do
    case Shodan.Repo.get_by(Host, [ip: ip, port: port]) do
      nil -> {Message.failed(m, {:host_does_not_exist, [ip: ip, port: port]}), default}
      h -> {m, Repo.preload(h, :processors)}
    end
  end

  # Step 2
  defp get_latest_processor_fragment(%Message{} = m, host, default) do
    processors = Enum.filter(host.processors,
      &String.ends_with?(Map.get(&1, :processor_name), "ValidationPipeline"))

    case Enum.sort_by(processors, &Map.get(&1, :timestamp)) do
      [ latest_pf | _ ] -> {m, latest_pf}
      _ -> {Message.failed(m, {:no_processor_fragments, nil}), default}
    end
  end

  # Step 3
  defp list_mapped_ports(%Message{data: {%Host{} = host, _}} = m, %ProcessorFragment{} = pf, default) do
    # Reconstruct struct
    service = struct!(Upnp.Service, pf.data.upnp_WANIPConn1_service_description)

    # Get location
    location = host
               |> Host.location_to_external_ip()
               |> Enum.at(0)
               |> URI.parse()

    # Expand Upnp service URL
    uri = Upnp.to_full_uri(service, location)
          |> Map.get(:controlURL, nil)
          |> URI.parse()

    # Fetch and return
    try do
      # For some reason, `:timeout.url()` is called on timeout, I don't get
      # why. `:timeout` does not exist as a module so it crashes, make a
      # proper error out of the exception.
      {m, Shodan.IgdProber.port_mappings(uri)}
    rescue
      UndefinedFunctionError -> {Message.failed(m, {:timeout, nil}), default}
    end
  end

  @impl true
  def handle_message(_processor, %Message{data: {%Host{} = host, _}} = m, _context) do
    pf = ProcessorFragment.bootstrap(__MODULE__)
    m = %Message{m | data: {host, pf}}

    # 1. Fetch host
    {m, host} = run_if_status_is_ok(m, &get_host/3, nil)

    # Check it's not one of our IPs
    m = run_if_status_is_ok(m, &BroadwayHelper.one_of_our_ips/3, host)
    
    # 2. Fetch latest processor fragment
    {m, data_pf} = run_if_status_is_ok(m, &get_latest_processor_fragment/3, host)

    # 3. Kickoff the recursive fetch
    Logger.debug("Starting port mapping enumeration")
    {m, mapped_ports} = run_if_status_is_ok(m, &list_mapped_ports/3, data_pf, %{})
    Logger.debug("#{length(Map.keys(mapped_ports))} mappings found")

    # Ecto screms when we try to insert structs, so we need to clean it up by transforming it to a clean Map
    res_mapped_ports = Enum.reduce(Map.keys(mapped_ports), %{}, fn x, acc ->
      map_from_struct = Map.from_struct(Map.get(mapped_ports, x, %Host{}))
      Map.put(acc, x, map_from_struct)
    end)

    Logger.debug("#{host.ip} made it to the end of processing with a status of #{inspect m.status}")

    res_pf = Map.put(pf, :data, %{mapped_ports: res_mapped_ports})

    %Message{m | data: {host, res_pf}}
    |> Message.put_batcher(:ecto)
  end

  def store_result!(%Message{} = m) do
    {host, pf} = m.data

    status = BroadwayHelper.extract_status(m)

    # Ecto screams because it expects a map but i can't figure out why ?! (data and status are both maps)
    pf = pf
         |> Map.put(:status, status)
         |> Map.drop([:__meta__, :host, :host_id])

    res_pf = ProcessorFragment.changeset(%ProcessorFragment{}, pf)
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

      # Send open ports' destination IP to SSDPDiscoveryPipeline
      {_, pf} = m.data
      hosts = Host.from_OpenPortsPipeline_mapped_ports(pf, :dst)
      BroadwayHelper.transform_and_push_message(SSDPDiscoveryPipeline, hosts)
    end
  end
end

defmodule Shodan.SSDPDiscoveryPipeline do
  require Logger
  require Host
  require ProcessorFragment

  import BroadwayHelper

  use Broadway

  alias Shodan.Repo
  alias Broadway.Message

  @moduledoc ~S"""
  `SSDPDiscoveryPipeline` sends the typical SSDP discovery message to 1900/udp
  Code logic:

    Host
    |> Ecto get host (check it's not one of our IPs)
    |> Perform scan
    |> Ecto save all results

  # Failure reason and format in saved status messages

    * Step 1: `{:one_of_our_ips, nil}`
    * Step 2: `{:timeout, nil}`
    * Otherwise: `{failed_unknown_reason: Broadway.Message}`

  # Improvements to be made (TODO maybe)
  [X] Save the output in a database
  [ ] Integrate `telemetry`
  [ ] Integrate `spandex`
  """

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: SSDPDiscoveryPipeline,
      producer: [
        module: {Shodan.ShimProducer, []},
        transformer: {BroadwayHelper, :transform, []},
      ],
      processors: [
        default: [concurrency: 50, max_demand: 1],
      ],
      batchers: [
        ecto: [concurrency: 1, batch_size: 10],
      ]
    )
  end

  # Step 2
  defp ssdp_discovery_scan(%Message{} = m, host, default) do
    case Shodan.SSDPScanner.ssdp_discovery(host.ip) do
      {:ok, r} -> {m, r}
      {:error, :timeout} -> {Message.failed(m, {:timeout, nil}), default}
    end
  end

  @impl true
  def handle_message(_processor, %Message{data: {%Host{} = host, _}} = m, _context) do
    ## 1. Fetch host
    host = Repo.get_or_insert_host!(host)
    pf = ProcessorFragment.bootstrap(__MODULE__)
    m = %Message{m | data: {host, pf}}

    # Check it's not one of our IPs
    m = run_if_status_is_ok(m, &BroadwayHelper.one_of_our_ips/3, host)
    
    # 2. SSDP Discovery Scan host
    {m, response} = run_if_status_is_ok(m, &ssdp_discovery_scan/3, host)

    res_pf = Map.put(pf, :data, %{response: response})

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
    Logger.debug("Got #{length(messages)} failed messages")
    Enum.map(messages, &store_result!(&1))
  end

  @impl true
  def handle_batch(:ecto, messages, _batch_info, _context) do
    Logger.debug("Got #{length(messages)} successful messages")
    Enum.map(messages, &store_result!(&1))
  end
end

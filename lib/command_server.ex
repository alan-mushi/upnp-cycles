defmodule CommandServer do
  require Logger
  require BroadwayHelper

  import Ecto.Query

  use GenServer

  alias Shodan.Repo

  def start_link(_opts) do
    Logger.info("Starting #{__MODULE__} on node #{inspect Node.self()}")
    GenServer.start_link(__MODULE__, :ok, name: CommandServer)
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call(:ping, _from, state) do
    {:reply, :pong, state}
  end

  #
  # ValidationPipeline
  #

  @impl true
  def handle_call({:feed_validation_pipeline_from_file, filename}, _from, state) do
    Logger.info("Feeding the ValidationPipeline from '#{filename}'")

    filename
    |> File.stream!()
    |> Stream.map(&Host.from_json(&1))
    |> Stream.chunk_every(100)
    |> Stream.map(&BroadwayHelper.transform_and_push_messages(ValidationPipeline, &1))
    |> Stream.run()

    {:reply, {:ok, filename}, state}
  end

  #
  # OpenPortsPipeline
  #

  @impl true
  def handle_call(:feed_open_ports_pipeline, _from, state) do
    Logger.info("Feedind OpenPortsPipeline from open ports in the database")

    q = from p0 in ProcessorFragment,
      distinct: :host_id,
      where: p0.status == ^%{ok: "ok"} and p0.processor_name == ^"ValidationPipeline",
      order_by: [desc: p0.timestamp]

    res = Repo.all(q)
          |> Repo.preload(:host)
          |> Enum.map(&Map.get(&1, :host))

    BroadwayHelper.transform_and_push_messages(OpenPortsPipeline, res)

    {:reply, {:ok, length(res)}, state}
  end

  #
  # Shodan API
  #

  @impl true
  def handle_call({:search_all, query, start_page}, _from, state) do
    Logger.info("Querying Shodan for '#{query}' starting at page #{start_page}")
    res = Shodan.APIService.search_all(query, start_page)
    {:reply, res, state}
  end

  @impl true
  def handle_call(:check_credit, _from, state) do
    {:ok, query_credits} = Shodan.APIService.check_credit()
    {:reply, {:ok, query_credits}, state}
  end

  #
  # SSDPDiscoveryPipeline
  #

  @impl true
  def handle_call({:ssdp_discovery_scan, :json, filename}, _from, state) do
    Logger.info("Feeding the SSDPDiscoveryPipeline from '#{filename}'")

    filename
    |> File.stream!()
    |> Stream.map(&Host.from_json(&1))
    |> Stream.chunk_every(100)
    |> Stream.map(&BroadwayHelper.transform_and_push_messages(SSDPDiscoveryPipeline, &1))
    |> Stream.run()

    {:reply, {:ok, filename}, state}
  end

  @impl true
  def handle_call({:ssdp_discovery_scan, :db, _}, _from, state) do
    Logger.info("Feeding the SSDPDiscoveryPipeline from all hosts in the database with a valid port")

    from(h in Host, where: h.port == ^1900)
    |> Repo.all()
    |> Enum.chunk_every(100)
    |> Enum.map(&BroadwayHelper.transform_and_push_messages(SSDPDiscoveryPipeline, &1))

    {:reply, {:ok, :db}, state}
  end

  @impl true
  def handle_call({:ssdp_discovery_scan, :db_mapped_ports, _}, _from, state) do
    Logger.info("Feeding the SSDPDiscoveryPipeline from all hosts in the database with mapped_ports as resolved by OpenPortsPipeline")

    hosts = Repo.get_mapped_ports()
            |> Enum.reduce([], fn pf, acc ->
              pf = Repo.preload(pf, :host)
              target_hosts = Host.from_OpenPortsPipeline_mapped_ports(pf, :dst)
                            |> Enum.filter(&Kernel.!=(&1.ip, pf.host.ip))
              acc ++ target_hosts
            end)

    hosts
    |> Enum.uniq_by(fn %Host{ip: ip, port: port} -> "#{ip}:#{port}" end)
    |> Enum.chunk_every(100)
    |> Enum.map(&BroadwayHelper.transform_and_push_messages(SSDPDiscoveryPipeline, &1))

    {:reply, {:ok, length(hosts)}, state}
  end

  @impl true
  def handle_call({:ssdp_discovery_scan, :one_ip, ip}, _from, state) do
    Logger.info("Feeding the SSDPDiscoveryPipeline with one ip: #{ip}")

    BroadwayHelper.transform_and_push_message(SSDPDiscoveryPipeline, %Host{ip: ip, port: 1900})
    {:reply, {:ok, ip}, state}
  end

  @impl true
  def handle_call({:pretty_print, :list_mapped_ports, _}, _from, state) do
    Logger.info("Returning the pretty printed list of mapped_ports")

    res = Repo.get_mapped_ports()
          |> Repo.preload(:host)
          |> Enum.reduce([], fn pf, acc ->
            m = Map.get(pf.data, :mapped_ports, %{})
            acc ++ Enum.map(m, &pp_mapped_port(&1, pf.host, pf.timestamp))
          end)


    {:reply, {:ok, res}, state}
  end

  #
  # Pretty Print
  #

  defp pp_mapped_port({id, mapping}, %Host{ip: ip}, timestamp) do
    %{
      NewInternalClient: host,
      NewInternalPort: local_port,
      NewPortMappingDescription: desc,
      NewProtocol: proto,
      NewExternalPort: external_port,
      NewRemoteHost: remoteIp
    } = mapping

    remoteIp = if remoteIp == "", do: "*"

    "[#{timestamp} | Host #{ip} | #{id} | #{proto}] #{remoteIp}:#{external_port} => #{host}:#{local_port}\tDesc: #{desc}"
  end

  defp pp_mapped_port({_, %{}}, _, _), do: ""
end

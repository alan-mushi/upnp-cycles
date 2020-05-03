defmodule CommandClient do
  require Logger

  import GenServer

  #@node_name :"shodan@localhost"
  @node_name :"shodan@127.0.0.1"
  @server_name CommandServer
  @remote_genserver {@server_name, @node_name}

  defp check_connection_to_remote_node() do
    case Node.ping(@node_name) do
      :pong ->
        Logger.debug("Connected to #{@node_name}")
        :pong

      :pang ->
        Logger.error("Could not connect to #{@node_name}")
        :pang
    end
  end

  #
  # ValidationPipeline
  #

  def feed_validation_pipeline_from_file(filename) do
    :pong = check_connection_to_remote_node()
    GenServer.call(@remote_genserver, {:feed_validation_pipeline_from_file, filename})
  end

  #
  # OpenPortsPipeline
  #

  def feed_open_ports_pipeline() do
    :pong = check_connection_to_remote_node()
    GenServer.call(@remote_genserver, :feed_open_ports_pipeline)
  end

  #
  # Shodan API
  #

  def search_all_query(query, start_page \\ 1) do
    :pong = check_connection_to_remote_node()
    GenServer.call(@remote_genserver, {:search_all, query, start_page})
  end

  def check_credit() do
    :pong = check_connection_to_remote_node()
    {:ok, query_credits} = GenServer.call(@remote_genserver, :check_credit)
    Logger.info("Remaining query credits: #{query_credits}")
  end

  #
  # SSDPDiscoveryPipeline
  #

  def ssdp_scan({:json_file, filename}) do
    GenServer.call(@remote_genserver, {:ssdp_discovery_scan, :json, filename})
  end

  def ssdp_scan(:db) do
    GenServer.call(@remote_genserver, {:ssdp_discovery_scan, :db, nil})
  end

  def ssdp_scan({:ip, ip}) do
    GenServer.call(@remote_genserver, {:ssdp_discovery_scan, :one_ip, ip})
  end

  def ssdp_scan(:db_mapped_ports) do
    {:ok, num} = GenServer.call(@remote_genserver, {:ssdp_discovery_scan, :db_mapped_ports, nil})
    Logger.info("#{num} hosts from OpenPortsPipeline mapped_ports passed to SSDPDiscoveryPipeline")
  end

  #
  # Pretty printing
  #

  def pretty_print(:list_mapped_ports) do
    {:ok, res} = GenServer.call(@remote_genserver, {:pretty_print, :list_mapped_ports, nil})
    Enum.map(res, &IO.puts(&1))
  end
end

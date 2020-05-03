defmodule Shodan.SSDPDiscoveryPipeline.Test do
  use ExUnit.Case
  require Logger
  import BroadwayHelper
  doctest Shodan.SSDPDiscoveryPipeline

  @filename "./test/assets/host_upnp_port_filtering.lst"

  #
  # Mock SSDP endpoint
  # I don't get *why* it's only running once but actually that's not much of an
  # issue for the test.
  #
  defmodule MockSSDP do
    use GenServer
    @filename "./test/assets/host_upnp_port_filtering.lst"

    def start_link(port) do
      GenServer.start_link(__MODULE__, port)
    end

    def init(_arg) do
      {:ok, ip} = :inet.parse_address('127.0.0.3')
      :gen_udp.open(1900, [:binary, :inet, ip: ip, active: true])
    end

    def handle_info({:udp, rsock, raddr, rport, data}, sock) do
      Logger.debug("Got the following request: #{data}")
      reply = File.stream!(@filename)
              |> Stream.map(&Host.from_json(&1))
              |> Stream.take(1)
              |> Enum.to_list()
              |> Enum.at(0)
              |> Map.from_struct()
              |> get_in([:injectors, :shodan, :data])

      reply = case reply do
        nil -> ""
        v -> Enum.join(v, "\r\n")
      end

      :ok = :gen_udp.send(rsock, raddr, rport, String.to_charlist(reply))

      {:noreply, sock}
    end
  end

  setup do
    [mock_ssdp: start_supervised!(MockSSDP)]
  end

  test "try scanning SSDP on two hosts" do
    [h1, h2] = File.stream!(@filename)
               |> Stream.map(&Host.from_json(&1))
               |> Stream.take(2)
               |> Enum.to_list

    hosts = [
      {Map.put(h1, :ip, "127.0.0.3"), nil},
      {Map.put(Map.put(h2, :ip, "127.0.0.4"), :port, 80), nil},
    ]

    ref = Broadway.test_messages(SSDPDiscoveryPipeline, hosts)
    assert_receive {:ack, ^ref, [], [failed]}, 10_000
    assert BroadwayHelper.extract_failed_code(failed) == {:one_of_our_ips, nil}
    assert_receive {:ack, ^ref, [], [failed]}, 10_000
    assert BroadwayHelper.extract_failed_code(failed) == {:one_of_our_ips, nil}

    IPUtils.clear_cached_addrs()

    ref = Broadway.test_messages(SSDPDiscoveryPipeline, hosts)
    assert_receive {:ack, ^ref, successful, []}, 10_000
    assert Enum.count(successful) == 1
    assert_receive {:ack, ^ref, [], [failed]}, 10_000
    assert BroadwayHelper.extract_failed_code(failed) == {:timeout, nil}
  end
end

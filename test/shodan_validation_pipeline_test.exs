defmodule Shodan.ValidationPipeline.Test do
  use ExUnit.Case
  require Logger
  doctest Shodan.ValidationPipeline

  @filename "./test/assets/host_upnp_port_filtering.lst"

  test "try sending one message" do
    [h1, h2, h3] = File.stream!(@filename)
            |> Stream.map(&Host.from_json(&1))
            |> Stream.take(3)
            |> Enum.to_list

    hosts = [
      {Map.put(h1, :ip, "127.0.0.1"), nil},
      {Map.put(h2, :ip, "127.0.0.2"), nil},
      {Map.put(Map.put(h3, :port, 80), :ip, "127.0.0.1"), nil},
    ]

    ref = Broadway.test_messages(ValidationPipeline, hosts)

    assert_receive {:ack, ^ref, successful, failed}, 100_000
    assert Enum.count(successful) == 0
    assert Enum.count(failed) == 3

    expected = %{:not_upnp_port => 1, :fetch_failed => 2}
    found  = Enum.reduce(failed, %{}, fn x, acc -> 
               {:failed, {reason, _details}} = Map.get(x, :status)
               Map.put(acc, reason, Map.get(acc, reason, 0) + 1)
             end)

    assert found == expected
  end

end

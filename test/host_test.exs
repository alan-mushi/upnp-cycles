defmodule Host.Test do
  use ExUnit.Case
  doctest Host

  @filename "./test/assets/host_upnp_port_filtering.lst"

  test "from_json" do
    assert_raise FunctionClauseError, fn -> Host.from_json(1) end
    assert_raise FunctionClauseError, fn -> Host.from_json("") end
    assert %Host{country: nil, injectors: %{}, ip: nil, port: nil} = Host.from_json("{}")
  end

  def host_stream(filename \\ @filename) do
    File.stream!(filename)
    |> Stream.map(&Host.from_json(&1))
  end

  test "upnp port filtering" do
    total = host_stream()
          |> Enum.to_list()
          |> Enum.count()
    assert total == 100

    res = host_stream()
          |> Stream.filter(&Host.is_upnp_port(&1))
          |> Enum.to_list()
          |> Enum.count()
    assert res == 92
  end

  test "location header present in shodan data" do
    res = host_stream()
          |> Stream.filter(&Host.is_upnp_port(&1))
          |> Stream.filter(&Host.has_location_header?(&1))
          |> Enum.to_list()
    assert Enum.count(res) == 92
  end

  test "extract location header" do
    url = "http://testing:8989/blahhh"
    assert {:ok, url} = Host.extract_location_url("LOCATION:" <> url)
    assert {:ok, url} = Host.extract_location_url("Location: " <> url)
    assert {:ok, url} = Host.extract_location_url("LocaTION:                " <> url)
    assert {:error, x} = Host.extract_location_url("Location " <> url)
    assert {:error, x} = Host.extract_location_url("Loc:ation " <> url)
  end

  test "replace host in location for external IP" do
    host = host_stream() |> Enum.take(1) |> Enum.at(0)

    old_loc = Host.get_location_headers(host) |> Enum.at(0)
    new_loc = Host.location_to_external_ip(host) |> Enum.at(0)

    assert old_loc != new_loc
    assert new_loc == "http://77.49.116.164:5555/DeviceDescription.xml"
  end
end

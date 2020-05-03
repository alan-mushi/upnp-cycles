defmodule Shodan.Api.Test do
  use ExUnit.Case
  doctest Shodan

  @moduletag timeout: :infinity

  @tag :network
  test "api-info" do
    Shodan.API.api_info()
    |> IO.inspect
  end

  @tag :network
  test "hosts search 'igd' first page" do
    Shodan.API.host_search("igd")
    |> IO.inspect
  end

  @tag :network
  test "query all" do
    file = File.open!("./test_all_hosts_igd.lst", [:delayed_write, :write, :utf8])

    Shodan.API.host_search_all("igd")
    |> Stream.map(&(Shodan.HostExtractor.match_to_host(&1)))
    |> Stream.each(&(IO.puts(file, Poison.encode!(&1))))
    |> Stream.run

    File.close file
  end
end

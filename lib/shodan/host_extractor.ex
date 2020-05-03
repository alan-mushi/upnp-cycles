defmodule Shodan.HostExtractor do
  require Host

  def match_to_host(match) do
    data =
      match[:data]
      |> String.trim("\r\n")
      |> String.split("\r\n")

    {:ok, timestamp} = NaiveDateTime.from_iso8601(match[:timestamp])

    %Host{
      ip: match[:ip_str],
      port: match[:port],
      country: match[:location][:country_name],
      injectors: %{shodan: %{data: data, timestamp: timestamp}}
    }
  end
end

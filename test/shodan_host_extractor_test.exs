defmodule Shodan.HostExtractor.Test do
  use ExUnit.Case

  test "match to host" do
    match = "{\"transport\":\"udp\",\"timestamp\":\"2020-04-13T00:26:19.832432\",\"port\":1900,\"os\":null,\"org\":\"Tv Sat 2002 Srl\",\"location\":{\"region_code\":\"BZ\",\"postal_code\":null,\"longitude\":26.6833,\"latitude\":45.2833,\"dma_code\":null,\"country_name\":\"Romania\",\"country_code3\":null,\"country_code\":\"RO\",\"city\":\"Berca\",\"area_code\":null},\"isp\":\"Tv Sat 2002 Srl\",\"ip_str\":\"37.156.227.117\",\"ip\":631038837,\"hostnames\":[],\"hash\":-1905956668,\"domains\":[],\"data\":\"HTTP/1.1 200 OK\\r\\nCACHE-CONTROL: max-age = 120\\r\\nEXT: \\r\\nLOCATION: http://192.168.10.1:80/UPnP/IGD.xml\\r\\nST: upnp:rootdevice\\r\\nSERVER: System/1.0 UPnP/1.0 IGD/1.0\\r\\nUSN: uuid:IGD{722696eb-73c2-4d55-ae59-ad48e0a6b7aa}0810745B877C::upnp:rootdevice\\r\\n\\r\\n\",\"asn\":\"AS41496\",\"_shodan\":{\"ptr\":true,\"options\":{},\"module\":\"upnp\",\"id\":null,\"crawler\":\"a1d7c8633bbc09815656eb22f5b59d9d5164fb2e\"}}"
            |> Poison.decode!(keys: :atoms)

    host = Shodan.HostExtractor.match_to_host(match)

    assert host.ip == "37.156.227.117"
    assert host.port == 1900
    assert host.country == "Romania"

    location_headers = Host.get_location_headers(host)
    location_extracted = location_headers |> Enum.at(0) |> Host.extract_location_url
    assert {:ok, "http://192.168.10.1:80/UPnP/IGD.xml"} == location_extracted
    assert Host.has_location_header?(host) == true
  end

  test "match all to hosts" do
    require Poison

    hosts =
      File.read!("./test/assets/response.json")
      |> Poison.decode!(keys: :atoms)
      |> Map.get(:matches)
      |> Enum.map(&Shodan.HostExtractor.match_to_host(&1))

    assert Enum.count(hosts) == 100

    upnp_with_location_header = hosts
                                |> Enum.filter(&Host.is_upnp_port(&1))
                                |> Enum.filter(&Host.has_location_header?(&1))

    assert Enum.count(upnp_with_location_header) == 98
  end
end

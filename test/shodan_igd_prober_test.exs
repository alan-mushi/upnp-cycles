#
# TODO: use the Bypass lib for this
#
defmodule Shodan.IgdProber.Test do
  use ExUnit.Case

  @freebox_device File.read!(Path.expand("./test/assets/freebox-device.xml"))
  @freebox_service_wan_ip File.read!(Path.expand("./test/assets/freebox-wan_ip_connection.xml"))

  #
  # Fetching
  #

  @tag :off_github
  test "fetch all igd definitions" do
    File.stream!("./test/various/test_all_hosts_igd.lst", [encoding: :utf8], :line)
    |> Stream.take(5)
    |> Flow.from_enumerable()
    |> Flow.map(&(Poison.decode!(&1, as: Host)))
    |> Flow.map(&(IO.inspect(&1)))
    |> Flow.run()
  end

  @tag :network
  test "fetch freebox IGD" do
    "http://192.168.0.254:5678/desc/root"
    |> URI.parse
    |> Shodan.IgdProber.get()
    |> IO.inspect
  end

  #
  # Validation
  #

  test "freebox xsd-compliant" do
    assert Shodan.IgdProber.is_valid_device?(@freebox_device) == true
    assert Shodan.IgdProber.is_valid_service?(@freebox_service_wan_ip) == true

    assert Shodan.IgdProber.is_valid_device?(@freebox_service_wan_ip) == false
    assert Shodan.IgdProber.is_valid_service?(@freebox_device) == false
  end

  #
  # Data extraction
  #
 
  test "freebox extract all upnp services" do
    services = Shodan.IgdProber.parse_xml_response(@freebox_device)
               |> Shodan.IgdProber.extract_all_service()

    assert services == [
      %Upnp.Service{
        SCPDURL: "/desc/l3f",
        controlURL: "/control/l3f",
        eventSubURL: "/event/l3f",
        serviceId: "urn:upnp-org:serviceId:L3Forwarding1",
        serviceType: "urn:schemas-upnp-org:service:Layer3Forwarding:1"
      },
      %Upnp.Service{
        SCPDURL: "/desc/wan_common_ifc",
        controlURL: "/control/wan_common_ifc",
        eventSubURL: "/event/wan_common_ifc",
        serviceId: "urn:upnp-org:serviceId:WANCommonIFC1",
        serviceType: "urn:schemas-upnp-org:service:WANCommonInterfaceConfig:1"
      },
      %Upnp.Service{
        SCPDURL: "/desc/wan_ip_connection",
        controlURL: "/control/wan_ip_connection",
        eventSubURL: "/event/wan_ip_connection",
        serviceId: "urn:upnp-org:serviceId:WANIPConn1",
        serviceType: "urn:schemas-upnp-org:service:WANIPConnection:1"
      }
    ]

  end

  test "freebox extract WANIPConn1 upnp service to full uri" do
    base = "http://192.168.0.254:5678"
    uri = URI.parse(base <> "/aaaa")
    services = Shodan.IgdProber.parse_xml_response(@freebox_device)
               |> Shodan.IgdProber.extract_all_service()

    assert length(services) == 3

    s = services
        |> Enum.at(-1)
        |> Upnp.Service.to_full_uri(uri)

    assert Map.get(s, :SCPDURL)     == base <> "/desc/wan_ip_connection"
    assert Map.get(s, :controlURL)  == base <> "/control/wan_ip_connection"
    assert Map.get(s, :eventSubURL) == base <> "/event/wan_ip_connection"
  end

  test "freebox extract WANIPConn1 upnp actions" do
    actions = @freebox_service_wan_ip
              |> Shodan.IgdProber.parse_xml_response()
              |> Shodan.IgdProber.extract_all_action()
    assert length(actions) == 11

    %Upnp.Action{argumentList: args} = actions
                                       |> Enum.filter(&Shodan.IgdProber.is_AddPortMapping?(&1))
                                       |> Enum.at(0)
    assert length(args) == 8
  end

  @tag :network
  test "freebox WANIPConnection GetGenericPortMappingEntry" do
    # TODO: setup Bypass or flask server to respond
    mappings = "http://192.168.0.254:5678/control/wan_ip_connection"
               |> URI.parse
               |> Shodan.IgdProber.port_mappings()
               |> IO.inspect

    assert length(mappings) == 2
  end
end

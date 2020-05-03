defmodule Shodan.IgdProber do
  require Logger
  require Upnp
  import Meeseeks.XPath

  @service_wanipconnection_1 "urn:schemas-upnp-org:service:WANIPConnection:1"

  @xsd_device Path.expand("upnp_schemas/device-1-0.xsd")
  @xsd_service Path.expand("upnp_schemas/service-1-0.xsd")
  @on_load :validate_xsd

  # Just to ensure we have all we need to perform validation
  def validate_xsd() do
    [@xsd_device, @xsd_service]
    |> Enum.reduce(:ok, fn f, acc -> 
      case {acc, :erlsom.compile_xsd_file(f)} do
        {:ok, {:ok, _}} -> :ok
        _ -> :abort
      end
    end)
  end

  #
  # Fetching
  #

  @spec http_client() :: Tesla.Client.t()
  defp http_client() do
    middleware = [
      Tesla.Middleware.KeepRequest,
      Tesla.Middleware.Logger,
      {Tesla.Middleware.Retry, [delay: 1_000, max_delay: 3_000]},
      {Tesla.Middleware.FollowRedirects, [max_redirects: 0]},
      {Tesla.Middleware.Headers, [{"User-Agent", "Mozilla/5.0"}]},
    ]
    Tesla.client(middleware, {Tesla.Adapter.Hackney, recv_timeout: 5_000})
  end

  @spec get(URI.t()) :: Tesla.Env.result()
  def get(%URI{} = url) do
    client = http_client()
    Logger.debug("Fetching #{url}")
    Tesla.get(client, URI.to_string(url))
  end

  defp soap_get_port_mapping(%URI{} = url, service, index) do
    headers = [
      {"Content-Type", "text/xml;charset=\"utf-8\""},
      {"Soapaction", "\"#{service}#GetGenericPortMappingEntry\""},
    ]

    payload = """
              <?xml version="1.0" encoding="utf-8" standalone="yes"?>
              <s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
              <s:Body>
                <u:GetGenericPortMappingEntry xmlns:u="#{service}">
                  <NewPortMappingIndex>#{index}</NewPortMappingIndex>
                </u:GetGenericPortMappingEntry>
              </s:Body>
              </s:Envelope>
              """

    # We have to use Hackney here, otherwise httpc overwrites our content-type with an empty value
    http_client()
    |> Tesla.post(URI.to_string(url), payload, headers: headers)
  end

  #
  # Validation
  # * device
  # * service
  #
  # Compiling a schema for each verification is kind of lame, move validation to a GenServer ?
  #
  # No SOAP validation for now
  #

  defp validate_doc_schema!(doc, schema) do
    Logger.debug("Verifying doc with XSD schema #{schema}")

    {:ok, model} = :erlsom.compile_xsd_file(schema)

    case :erlsom.scan(doc, model) do
      {:ok, _, '\n'} -> true
      {:ok, _, []} -> true
      _ -> false
    end
  end

  def is_valid_device?(doc), do: validate_doc_schema!(doc, @xsd_device)

  def is_valid_service?(doc), do: validate_doc_schema!(doc, @xsd_service)

  #
  # Data extraction
  # * services description
  # * actions description
  # * GetGenericPortMappingEntryResponse SOAP response
  #

  @spec parse_xml_response(Tesla.Env.body()) :: Meeseeks.Document.t()
  def parse_xml_response(resp) do
    Meeseeks.parse(resp, :xml)
  end

  def extract_all_service(%Meeseeks.Document{} = doc) do
    Meeseeks.all(doc, xpath("//service"))
    |> Enum.map(&Upnp.to_service_struct(&1))
  end

  def extract_all_action(%Meeseeks.Document{} = doc) do
    Meeseeks.all(doc, xpath("//actionList/action"))
    |> Enum.map(&Upnp.to_action_struct(&1))
  end

  def is_WANIPConn1?(%Upnp.Service{serviceId: serviceId}), do: "urn:upnp-org:serviceId:WANIPConn1" == serviceId
  def is_AddPortMapping?(%Upnp.Action{name: name}), do: "AddPortMapping" == name
  def is_GetGenericPortMappingEntry?(%Upnp.Action{name: name}), do: "GetGenericPortMappingEntry" == name

  defp parse_GetGenericPortMappingEntryResponse_response({:ok, %Tesla.Env{status: 200} = resp}, index, acc) do
    mapping = resp.body
              |> Meeseeks.parse(:xml)
              |> Meeseeks.one(xpath("/Envelope/Body/GetGenericPortMappingEntryResponse"))
              |> Upnp.to_GetGenericPortMappingEntryResponse_struct()

    case mapping do
      nil -> {:halt, acc}
      mapping -> {:cont, Map.put(acc, index, mapping)}
    end
  end

  # End of the mapped ports
  defp parse_GetGenericPortMappingEntryResponse_response({:ok, %Tesla.Env{status: 500}}, _index, acc), do: {:halt, acc}

  defp parse_GetGenericPortMappingEntryResponse_response({:error, r}, index, acc) do
    Logger.error("Got an error for the following request: #{r.url}, index: #{index}\n#{r}")
    {:halt, acc}
  end

  #
  # Get all port mappings
  # * Send/receive SOAP messages
  # * Responses to struct
  # * Iter until HTTP/500 (end of mappings)
  #

  @spec port_mappings(URI.t()) :: Map.t()
  def port_mappings(%URI{} = uri) do
    Enum.reduce_while(0..65535, %{}, fn x, acc ->
      soap_get_port_mapping(uri, @service_wanipconnection_1, x)
      |> parse_GetGenericPortMappingEntryResponse_response(x, acc)
    end)
  end
end

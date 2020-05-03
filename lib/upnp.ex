defmodule Upnp do
  import Meeseeks.XPath

  def get_struct_fields(module) do
    Map.keys(module)
    |> Enum.filter(&Kernel.!=(&1, :__struct__))
  end

  def to_struct(%Meeseeks.Result{} = res, module) do
    get_struct_fields(module)
    |> Enum.reduce(module, fn tag, acc ->
      v = Meeseeks.text(Meeseeks.one(res, xpath("./#{tag}")))
      Map.put(acc, tag, v)
    end)
  end

  def to_full_uri(struct, %URI{} = uri) do
    get_struct_fields(struct)
    |> Enum.filter(&String.ends_with?(Atom.to_string(&1), "URL"))
    |> Enum.reduce(struct, fn field, acc ->
      new_uri = uri
                |> URI.merge(Map.get(acc, field, "/"))
                |> URI.to_string()
      Map.put(acc, field, new_uri)
    end)
  end

  defmodule Device do
    defstruct [:friendlyName, :manufacturer, :modelURL, :modelName, :modelNumber, :serialNumber]
  end

  defmodule Service do
    defstruct [:serviceType, :serviceId, :SCPDURL, :controlURL, :eventSubURL]

    @spec to_full_uri(Upnp.Service, URI.t()) :: Upnp.Service
    def to_full_uri(%__MODULE__{} = service, %URI{} = uri), do: Upnp.to_full_uri(service, uri)
  end

  defmodule Action do
    defstruct [:name, argumentList: []]

    def to_action_struct(%Meeseeks.Result{} = res) do
      # Need to account for the argumentList
      a = %Upnp.Action{}

      v = Meeseeks.text(Meeseeks.one(res, xpath("./name")))
      a = Map.put(a, :name, v)

      v = res
          |> Meeseeks.all(xpath("./argumentList/argument"))
          |> Enum.map(&Upnp.to_argument_struct(&1))
      Map.put(a, :argumentList, v)
    end
  end

  defmodule Argument do
    defstruct [:name, :direction, :relatedStateVariable]
  end

  defmodule GetGenericPortMappingEntryResponse do
    defstruct [
      :NewRemoteHost,
      :NewExternalPort,
      :NewProtocol,
      :NewInternalPort,
      :NewInternalClient,
      :NewEnabled,
      :NewPortMappingDescription,
      :NewLeaseDuration
    ]
  end

  # Meh... it's ugly... can we do better ?
  def to_device_struct(%Meeseeks.Result{} = res), do: Upnp.to_struct(res, %Upnp.Device{})
  def to_service_struct(%Meeseeks.Result{} = res), do: Upnp.to_struct(res, %Upnp.Service{})
  def to_action_struct(%Meeseeks.Result{} = res), do: Upnp.Action.to_action_struct(res)
  def to_argument_struct(%Meeseeks.Result{} = res), do: Upnp.to_struct(res, %Upnp.Argument{})
  def to_GetGenericPortMappingEntryResponse_struct(%Meeseeks.Result{} = res), do: Upnp.to_struct(res, %Upnp.GetGenericPortMappingEntryResponse{})
  # Some upnp servers don't return the expected error message but an empty SOAP body message
  def to_GetGenericPortMappingEntryResponse_struct(nil), do: nil
end

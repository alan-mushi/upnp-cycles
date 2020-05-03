defmodule Host do
  use Ecto.Schema

  @moduledoc ~S"""
  Struct representing a host, where it comes from (`:injectors`) and the
  results of intermediary processing that it underwent (`:processors`, in
  reverse order).
  """

  schema "hosts" do
    field :ip, :string, primary_key: true
    field :port, :integer, primary_key: true
    field :country, :string
    field :injectors, :map, default: %{}
    has_many :processors, ProcessorFragment
  end

  def changeset(host, params \\ %{}) do
    host
    |> Ecto.Changeset.cast(params, [:ip, :port, :country, :injectors])
    |> Ecto.Changeset.cast_assoc(:processors, with: &ProcessorFragment.changeset/2)
    |> Ecto.Changeset.validate_required([:ip, :port])
  end

  def extract_location_url(header) do
    [loc, url] = String.split(header, ":", parts: 2)

    case {String.downcase(loc, :ascii), String.trim(url)} do
      {"location", url} -> {:ok, url}
      x -> {:error, x}
    end
  end

  def is_location_header?(header) when header != "" do
    String.downcase(header, :ascii)
    |> String.starts_with?("location:")
  end
  def is_location_header?(_), do: false

  def get_location_headers(%Host{} = host) do
    host.injectors
    |> Map.values()
    |> Enum.reduce([], fn injector, acc -> injector.data ++ acc end)
    |> Enum.filter(&is_location_header?(&1))
  end

  def has_location_header?(%Host{} = host) do
    get_location_headers(host)
    |> Enum.empty?
    |> Kernel.not
  end

  def is_upnp_port(%Host{port: 1900}), do: true
  def is_upnp_port(_), do: false

  def from_json(j) when is_bitstring(j) and j != "", do: Poison.decode!(j, as: %Host{}, keys: :atoms)

  def from_OpenPortsPipeline_mapped_ports(pf, :src) do
    from_OpenPortsPipeline_mapped_ports(pf, :NewRemoteHost, :NewExternalPort)
  end

  def from_OpenPortsPipeline_mapped_ports(pf, :dst) do
    from_OpenPortsPipeline_mapped_ports(pf, :NewInternalClient, :NewInternalPort)
  end

  defp from_OpenPortsPipeline_mapped_ports(%ProcessorFragment{data: %{mapped_ports: mapped_ports}}, host_key, port_key) do
    mapped_ports
    |> Map.values()
    |> Enum.reduce([], fn m, acc ->
      ip = Map.get(m, host_key)
      {port, ""} = Map.get(m, port_key, 0)
                   |> Integer.parse()

      case ip == "" or IPUtils.one_of_our_ips?(ip) or IPUtils.broadcast_ip?(ip) do
        true -> acc
        false -> [%Host{ip: ip, port: port} | acc]
      end
    end)
  end

  def location_to_external_ip(%Host{ip: ip} = host) do
    get_location_headers(host)
    |> Enum.map(&extract_location_url(&1))
    |> Enum.map(fn {:ok, url} -> URI.to_string(%{URI.parse(url) | host: ip}) end)
  end
end

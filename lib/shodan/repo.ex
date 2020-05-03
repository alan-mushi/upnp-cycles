defmodule Shodan.Repo do
  use Ecto.Repo,
    otp_app: :shodan,
    adapter: Ecto.Adapters.Postgres

  import Ecto.Query

  # Ecto does not support references on compound foreign keys 
  # so we need to get creative, this should be race-free
  def get_or_insert_host!(%Host{ip: ip, port: port} = host) do
    {:ok, res_host} = Shodan.Repo.transaction(fn ->
      fetched_host = Host
                     |> distinct([:ip, :port])
                     |> where([ip: ^ip, port: ^port])
                     |> Shodan.Repo.one()

      case fetched_host do
        nil -> Shodan.Repo.insert!(host)
        h -> h
      end
    end)

    res_host
  end

  defmodule JSON do
    @moduledoc ~S"""
    Postgrex decodes embedded schema with strings for JSON keys but using atoms
    is much easier so this module wraps decoding to allow _existing_ atoms.
    """
    defdelegate encode!(o), to: Poison
    defdelegate encode_to_iodata!(o), to: Poison
    def decode!(o), do: Poison.decode!(o, keys: :atoms)
  end

  def get_mapped_ports() do
    from(p in ProcessorFragment, where: p.processor_name == ^"OpenPortsPipeline" and p.data != ^%{mapped_ports: %{}})
    |> Shodan.Repo.all()
  end
end

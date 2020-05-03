defmodule ProcessorFragment do
  use Ecto.Schema

  schema "processor_fragments" do
    belongs_to :host, Host
    field :processor_name, :string
    field :timestamp, :utc_datetime_usec
    field :data, :map, default: %{}
    field :status, :map, default: %{}
  end

  def changeset(pf, params \\ %{}) do
    pf
    |> Ecto.Changeset.cast(params, [:processor_name, :timestamp, :data, :status])
    |> Ecto.Changeset.validate_required([:processor_name, :timestamp, :data])
  end

  def bootstrap(module \\ __MODULE__) do
    pretty_processor_name = module
                            |> to_string()
                            |> String.split(".")
                            |> List.last()
    %{
      timestamp: DateTime.utc_now(),
      processor_name: pretty_processor_name
    }
  end
end

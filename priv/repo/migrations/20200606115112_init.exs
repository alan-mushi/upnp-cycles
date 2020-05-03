defmodule Shodan.Repo.Migrations.Init do
  use Ecto.Migration

  def change do
    create table(:hosts) do
      add :ip, :string, null: false
      add :port, :integer, null: false
      add :country, :string
      add :injectors, :map
      add :processors, {:array, :map}, default: []
    end

    create table(:processor_fragments) do
      add :host_id, references(:hosts)
      add :processor_name, :string
      add :timestamp, :utc_datetime_usec
      add :data, :map
      add :status, :map
    end
  end
end

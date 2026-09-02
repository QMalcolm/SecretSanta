defmodule SecretSanta.Repo.Migrations.CreateExclusions do
  use Ecto.Migration

  def change do
    create table(:exclusions) do
      add :exchange_id, references(:exchanges, on_delete: :delete_all), null: false
      add :giver_id, references(:participants, on_delete: :delete_all), null: false
      add :excluded_id, references(:participants, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:exclusions, [:giver_id, :excluded_id])
    create index(:exclusions, [:exchange_id])
    create index(:exclusions, [:excluded_id])
  end
end

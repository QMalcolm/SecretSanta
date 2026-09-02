defmodule SecretSanta.Repo.Migrations.CreateExchanges do
  use Ecto.Migration

  def change do
    create table(:exchanges) do
      add :name, :string, null: false
      add :drawn_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end
  end
end

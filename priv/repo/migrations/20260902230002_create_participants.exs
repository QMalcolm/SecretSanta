defmodule SecretSanta.Repo.Migrations.CreateParticipants do
  use Ecto.Migration

  def change do
    create table(:participants) do
      add :exchange_id, references(:exchanges, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :email, :string, null: false
      add :recipient_id, references(:participants, on_delete: :nilify_all)
      add :last_sent_at, :utc_datetime
      add :last_error, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:participants, [:exchange_id, :name])
    create unique_index(:participants, [:exchange_id, :email])
    create index(:participants, [:recipient_id])
  end
end

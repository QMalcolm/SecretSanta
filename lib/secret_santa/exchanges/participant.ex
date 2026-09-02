defmodule SecretSanta.Exchanges.Participant do
  @moduledoc """
  Someone taking part in an exchange (spec.md §3).

  `recipient` is who they drew; it is nil until the exchange is drawn.
  `last_sent_at` and `last_error` track email delivery (spec.md §4.6).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias SecretSanta.Exchanges.Exchange

  schema "participants" do
    field :name, :string
    field :email, :string
    field :last_sent_at, :utc_datetime
    field :last_error, :string

    belongs_to :exchange, Exchange
    belongs_to :recipient, __MODULE__

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for the organizer adding or editing a participant."
  def changeset(participant, attrs) do
    participant
    |> cast(attrs, [:name, :email])
    |> update_change(:name, &trim/1)
    |> update_change(:email, &normalize_email/1)
    |> validate_required([:name, :email])
    |> validate_length(:name, max: 100)
    |> validate_length(:email, max: 160)
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> unique_constraint(:name,
      name: :participants_exchange_id_name_index,
      message: "is already in this exchange"
    )
    |> unique_constraint(:email,
      name: :participants_exchange_id_email_index,
      message: "is already in this exchange"
    )
  end

  defp trim(nil), do: nil
  defp trim(value), do: String.trim(value)

  defp normalize_email(nil), do: nil
  defp normalize_email(value), do: value |> String.trim() |> String.downcase()
end

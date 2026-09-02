defmodule SecretSanta.Exchanges.Exclusion do
  @moduledoc """
  A one-directional draw constraint: `giver` must not draw `excluded`
  (spec.md §3). Says nothing about whether `excluded` may draw `giver`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias SecretSanta.Exchanges.{Exchange, Participant}

  schema "exclusions" do
    belongs_to :exchange, Exchange
    belongs_to :giver, Participant
    belongs_to :excluded, Participant

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(exclusion, attrs) do
    exclusion
    |> cast(attrs, [:exchange_id, :giver_id, :excluded_id])
    |> validate_required([:exchange_id, :giver_id, :excluded_id])
    |> validate_not_self()
    |> unique_constraint([:giver_id, :excluded_id],
      name: :exclusions_giver_id_excluded_id_index,
      error_key: :excluded_id,
      message: "is already excluded for this giver"
    )
  end

  defp validate_not_self(changeset) do
    if get_field(changeset, :giver_id) == get_field(changeset, :excluded_id) do
      add_error(changeset, :excluded_id, "cannot be the giver themselves")
    else
      changeset
    end
  end
end

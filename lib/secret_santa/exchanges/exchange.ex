defmodule SecretSanta.Exchanges.Exchange do
  @moduledoc """
  A single Secret Santa gift exchange.

  An exchange is *open* until it is drawn, at which point `drawn_at` is set
  and it becomes immutable (spec.md §3, §4.4).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "exchanges" do
    field :name, :string
    field :drawn_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(exchange, attrs) do
    exchange
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, max: 200)
  end

  @doc "True if the exchange has not been drawn yet."
  def open?(%__MODULE__{drawn_at: nil}), do: true
  def open?(%__MODULE__{}), do: false
end

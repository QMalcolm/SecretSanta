defmodule SecretSanta.Exchanges do
  @moduledoc """
  The Exchanges context: everything about a gift exchange, its participants,
  and its exclusions.

  Mutations that only make sense before the draw return
  `{:error, :exchange_drawn}` when attempted on a drawn exchange, so callers
  never have to remember to check.
  """

  import Ecto.Query, warn: false
  alias SecretSanta.Repo

  alias SecretSanta.Exchanges.Exchange

  ## Exchanges

  @doc "Returns all exchanges, newest first."
  def list_exchanges do
    Repo.all(from e in Exchange, order_by: [desc: e.inserted_at, desc: e.id])
  end

  @doc "Gets a single exchange. Raises `Ecto.NoResultsError` if not found."
  def get_exchange!(id), do: Repo.get!(Exchange, id)

  @doc "Creates an open exchange."
  def create_exchange(attrs) do
    %Exchange{}
    |> Exchange.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Deletes an exchange and everything under it. Allowed in any state
  (spec.md §4.1).
  """
  def delete_exchange(%Exchange{} = exchange) do
    Repo.delete(exchange)
  end

  @doc "Returns a changeset for tracking exchange changes in a form."
  def change_exchange(%Exchange{} = exchange, attrs \\ %{}) do
    Exchange.changeset(exchange, attrs)
  end
end

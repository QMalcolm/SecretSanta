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

  alias SecretSanta.Exchanges.{Exchange, Participant}

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

  ## Participants

  @doc "Returns the participants of an exchange, alphabetically by name."
  def list_participants(%Exchange{id: exchange_id}) do
    Repo.all(
      from p in Participant,
        where: p.exchange_id == ^exchange_id,
        order_by: [asc: p.name, asc: p.id]
    )
  end

  @doc """
  Gets a single participant of the given exchange. Raises
  `Ecto.NoResultsError` if it does not exist or belongs to another exchange.
  """
  def get_participant!(%Exchange{id: exchange_id}, id) do
    Repo.get_by!(Participant, id: id, exchange_id: exchange_id)
  end

  @doc """
  Adds a participant to an open exchange.

  Returns `{:error, :exchange_drawn}` if the exchange has been drawn.
  """
  def create_participant(%Exchange{} = exchange, attrs) do
    with :ok <- ensure_open(exchange) do
      %Participant{exchange_id: exchange.id}
      |> Participant.changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc """
  Updates a participant's name or email. Only allowed while the exchange is
  open; returns `{:error, :exchange_drawn}` otherwise.
  """
  def update_participant(%Participant{} = participant, attrs) do
    with :ok <- ensure_open(participant) do
      participant
      |> Participant.changeset(attrs)
      |> Repo.update()
    end
  end

  @doc """
  Removes a participant from an open exchange, along with any exclusions
  that reference them. Returns `{:error, :exchange_drawn}` if the exchange
  has been drawn.
  """
  def delete_participant(%Participant{} = participant) do
    with :ok <- ensure_open(participant) do
      Repo.delete(participant)
    end
  end

  @doc "Returns a changeset for tracking participant changes in a form."
  def change_participant(%Participant{} = participant, attrs \\ %{}) do
    Participant.changeset(participant, attrs)
  end

  ## State guards

  defp ensure_open(%Exchange{} = exchange) do
    if Exchange.open?(exchange), do: :ok, else: {:error, :exchange_drawn}
  end

  defp ensure_open(%Participant{exchange_id: exchange_id}) do
    exchange_id |> get_exchange!() |> ensure_open()
  end
end

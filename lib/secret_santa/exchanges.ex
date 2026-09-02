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

  alias SecretSanta.Exchanges.{Exchange, Exclusion, Matching, Participant}

  @min_participants 3

  ## Exchanges

  @doc """
  Returns all exchanges, newest first, with `participant_count` filled in.
  """
  def list_exchanges do
    Repo.all(
      from e in Exchange,
        left_join: p in Participant,
        on: p.exchange_id == e.id,
        group_by: e.id,
        order_by: [desc: e.inserted_at, desc: e.id],
        select: %{e | participant_count: count(p.id)}
    )
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

  ## Exclusions

  @doc "Returns all exclusions of an exchange."
  def list_exclusions(%Exchange{id: exchange_id}) do
    Repo.all(from x in Exclusion, where: x.exchange_id == ^exchange_id, order_by: x.id)
  end

  @doc """
  Records that `giver` must not draw `excluded`. One-directional: to also
  stop `excluded` drawing `giver`, add the reverse explicitly.

  Both participants must belong to `exchange`, which must be open. Returns
  `{:error, :exchange_drawn}`, `{:error, :not_in_exchange}`, or
  `{:error, changeset}` for a self-exclusion or duplicate.
  """
  def add_exclusion(%Exchange{} = exchange, %Participant{} = giver, %Participant{} = excluded) do
    with :ok <- ensure_open(exchange),
         :ok <- ensure_members(exchange, [giver, excluded]) do
      %Exclusion{}
      |> Exclusion.changeset(%{
        exchange_id: exchange.id,
        giver_id: giver.id,
        excluded_id: excluded.id
      })
      |> Repo.insert()
    end
  end

  @doc """
  Removes the exclusion of `excluded` for `giver`, if any. Returns
  `{:error, :not_found}` if there was none and `{:error, :exchange_drawn}`
  if the exchange is drawn.
  """
  def remove_exclusion(%Exchange{} = exchange, %Participant{} = giver, %Participant{} = excluded) do
    with :ok <- ensure_open(exchange),
         %Exclusion{} = exclusion <-
           Repo.get_by(Exclusion,
             exchange_id: exchange.id,
             giver_id: giver.id,
             excluded_id: excluded.id
           ) || {:error, :not_found} do
      Repo.delete(exclusion)
    end
  end

  ## Drawing

  @typedoc """
  A reason the draw cannot happen right now (spec.md §4.3, §4.4).
  """
  @type blocker ::
          :exchange_drawn
          | {:too_few_participants, non_neg_integer()}
          | {:no_legal_recipient, Participant.t()}

  @doc "The smallest group that can be drawn."
  def min_participants, do: @min_participants

  @doc """
  Maps each participant id to the ids they are allowed to draw: everyone
  in the exchange except themselves and anyone they have excluded.

  Pure; takes already-loaded lists so the UI can recompute on every
  change without extra queries.
  """
  def legal_recipients(participants, exclusions) do
    ids = Enum.map(participants, & &1.id)

    excluded_by_giver =
      Enum.group_by(exclusions, & &1.giver_id, & &1.excluded_id)

    Map.new(ids, fn giver_id ->
      excluded = Map.get(excluded_by_giver, giver_id, [])
      {giver_id, Enum.reject(ids, &(&1 == giver_id or &1 in excluded))}
    end)
  end

  @doc """
  Everything currently preventing a draw, in display order, or `[]` if the
  draw button may be enabled. The `{:no_legal_recipient, participant}`
  blockers are the "live validation" of spec.md §4.3; a draw can still
  fail for non-obvious reasons (see `draw_exchange/1`).
  """
  @spec draw_blockers(Exchange.t()) :: [blocker]
  def draw_blockers(%Exchange{} = exchange) do
    draw_blockers(exchange, list_participants(exchange), list_exclusions(exchange))
  end

  @spec draw_blockers(Exchange.t(), [Participant.t()], [Exclusion.t()]) :: [blocker]
  def draw_blockers(%Exchange{} = exchange, participants, exclusions) do
    legal = legal_recipients(participants, exclusions)

    stuck =
      participants
      |> Enum.filter(&(Map.fetch!(legal, &1.id) == []))
      |> Enum.map(&{:no_legal_recipient, &1})

    List.flatten([
      if(Exchange.open?(exchange), do: [], else: :exchange_drawn),
      if(length(participants) < @min_participants,
        do: {:too_few_participants, length(participants)},
        else: []
      ),
      stuck
    ])
  end

  @doc """
  Makes the draw: assigns every participant a recipient honoring the
  exclusions and stamps `drawn_at`, all in one transaction (spec.md §4.4).

  Returns `{:ok, exchange}` with the updated exchange, or `{:error, reason}`
  where reason is a `t:blocker/0` or `{:no_valid_assignment, participants}`
  naming those left without a recipient when the exclusions are
  unsatisfiable in a non-obvious way. Nothing is written on error.
  """
  @spec draw_exchange(Exchange.t()) ::
          {:ok, Exchange.t()} | {:error, blocker | {:no_valid_assignment, [Participant.t()]}}
  def draw_exchange(%Exchange{id: id}) do
    Repo.transaction(fn ->
      # Reload inside the transaction so a stale struct cannot double-draw.
      exchange = get_exchange!(id)
      participants = list_participants(exchange)
      exclusions = list_exclusions(exchange)

      with [] <- draw_blockers(exchange, participants, exclusions),
           {:ok, assignment} <-
             participants |> legal_recipients(exclusions) |> Matching.perfect_matching() do
        Enum.each(participants, fn participant ->
          participant
          |> Ecto.Changeset.change(recipient_id: Map.fetch!(assignment, participant.id))
          |> Repo.update!()
        end)

        exchange
        |> Ecto.Changeset.change(drawn_at: DateTime.utc_now(:second))
        |> Repo.update!()
      else
        [blocker | _] ->
          Repo.rollback(blocker)

        {:error, unmatched_ids} ->
          unmatched = Enum.filter(participants, &(&1.id in unmatched_ids))
          Repo.rollback({:no_valid_assignment, unmatched})
      end
    end)
  end

  ## State guards

  # Always re-reads the exchange: the struct a caller holds may predate the
  # draw (another tab, a double click), and "immutable once drawn" has to
  # hold against stale callers, not just honest ones.
  defp ensure_open(%Exchange{id: exchange_id}), do: ensure_open_id(exchange_id)
  defp ensure_open(%Participant{exchange_id: exchange_id}), do: ensure_open_id(exchange_id)

  defp ensure_open_id(exchange_id) do
    if Exchange.open?(get_exchange!(exchange_id)), do: :ok, else: {:error, :exchange_drawn}
  end

  defp ensure_members(%Exchange{id: exchange_id}, participants) do
    if Enum.all?(participants, &(&1.exchange_id == exchange_id)),
      do: :ok,
      else: {:error, :not_in_exchange}
  end
end

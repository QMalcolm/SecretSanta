defmodule SecretSanta.Exchanges.Matching do
  @moduledoc """
  Pure assignment logic for a draw (spec.md §4.4).

  Given each giver's legal recipients, finds a random assignment in which
  every giver gives to exactly one recipient and every recipient receives
  from exactly one giver. Small cycles (A ↔ B) are allowed.

  Knows nothing about the database; the context builds the candidate map.
  """

  @typedoc "A giver id mapped to the ids it may draw."
  @type candidates :: %{term => [term]}

  @doc """
  Finds a random perfect matching over `candidates`.

  Returns `{:ok, assignment}` mapping each giver to its recipient, or
  `{:error, unmatched}` listing the givers that could not be assigned
  once a maximum matching had been found. The unmatched list is the best
  diagnostic available: at least those participants are "involved" in
  the infeasibility.
  """
  @spec perfect_matching(candidates) :: {:ok, %{term => term}} | {:error, [term]}
  def perfect_matching(candidates) when is_map(candidates) do
    shuffled =
      Map.new(candidates, fn {giver, recipients} -> {giver, Enum.shuffle(recipients)} end)

    {match, unmatched} =
      shuffled
      |> Map.keys()
      |> Enum.shuffle()
      |> Enum.reduce({%{}, []}, fn giver, {match, unmatched} ->
        case augment(giver, shuffled, match, MapSet.new()) do
          {:ok, match} -> {match, unmatched}
          {:error, _visited} -> {match, [giver | unmatched]}
        end
      end)

    case unmatched do
      [] -> {:ok, Map.new(match, fn {recipient, giver} -> {giver, recipient} end)}
      _ -> {:error, Enum.reverse(unmatched)}
    end
  end

  # Kuhn's augmenting-path step. `match` maps recipient => giver. Tries to
  # give `giver` a recipient, evicting and re-homing an existing giver if
  # that frees something up. `visited` stops us re-trying a recipient
  # within one augmentation.
  defp augment(giver, candidates, match, visited) do
    Enum.reduce_while(Map.fetch!(candidates, giver), {:error, visited}, fn recipient,
                                                                           {:error, visited} ->
      if MapSet.member?(visited, recipient) do
        {:cont, {:error, visited}}
      else
        visited = MapSet.put(visited, recipient)

        case Map.fetch(match, recipient) do
          :error ->
            {:halt, {:ok, Map.put(match, recipient, giver)}}

          {:ok, current} ->
            case augment(current, candidates, match, visited) do
              {:ok, match} -> {:halt, {:ok, Map.put(match, recipient, giver)}}
              {:error, visited} -> {:cont, {:error, visited}}
            end
        end
      end
    end)
  end
end

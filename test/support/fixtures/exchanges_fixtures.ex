defmodule SecretSanta.ExchangesFixtures do
  @moduledoc """
  Test helpers for creating entities via the `SecretSanta.Exchanges` context.
  """

  alias SecretSanta.Exchanges
  alias SecretSanta.Exchanges.Exchange
  alias SecretSanta.Repo

  def exchange_fixture(attrs \\ %{}) do
    {:ok, exchange} =
      attrs
      |> Enum.into(%{name: "Family #{System.unique_integer([:positive])}"})
      |> Exchanges.create_exchange()

    exchange
  end

  @doc """
  An exchange whose `drawn_at` is set, bypassing the draw itself. Useful
  for testing the immutability rules in isolation.
  """
  def drawn_exchange_fixture(attrs \\ %{}) do
    attrs
    |> exchange_fixture()
    |> Ecto.Changeset.change(drawn_at: DateTime.utc_now(:second))
    |> Repo.update!()
  end

  def participant_fixture(%Exchange{} = exchange, attrs \\ %{}) do
    n = System.unique_integer([:positive])

    {:ok, participant} =
      Exchanges.create_participant(
        exchange,
        Enum.into(attrs, %{name: "Person #{n}", email: "person#{n}@example.com"})
      )

    participant
  end
end

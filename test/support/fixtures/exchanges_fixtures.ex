defmodule SecretSanta.ExchangesFixtures do
  @moduledoc """
  Test helpers for creating entities via the `SecretSanta.Exchanges` context.
  """

  alias SecretSanta.Exchanges

  def exchange_fixture(attrs \\ %{}) do
    {:ok, exchange} =
      attrs
      |> Enum.into(%{name: "Family #{System.unique_integer([:positive])}"})
      |> Exchanges.create_exchange()

    exchange
  end
end

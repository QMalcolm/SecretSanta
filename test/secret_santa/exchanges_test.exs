defmodule SecretSanta.ExchangesTest do
  use SecretSanta.DataCase, async: true

  import SecretSanta.ExchangesFixtures

  alias SecretSanta.Exchanges
  alias SecretSanta.Exchanges.Exchange

  describe "exchanges" do
    test "list_exchanges/0 returns all exchanges, newest first" do
      older = exchange_fixture()
      newer = exchange_fixture()

      assert Enum.map(Exchanges.list_exchanges(), & &1.id) == [newer.id, older.id]
    end

    test "get_exchange!/1 returns the exchange with the given id" do
      exchange = exchange_fixture()
      assert Exchanges.get_exchange!(exchange.id) == exchange
    end

    test "create_exchange/1 with a name creates an open exchange" do
      assert {:ok, %Exchange{} = exchange} = Exchanges.create_exchange(%{name: "Family 2026"})
      assert exchange.name == "Family 2026"
      assert exchange.drawn_at == nil
      assert Exchange.open?(exchange)
    end

    test "create_exchange/1 requires a name" do
      assert {:error, changeset} = Exchanges.create_exchange(%{name: ""})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "delete_exchange/1 deletes the exchange" do
      exchange = exchange_fixture()
      assert {:ok, %Exchange{}} = Exchanges.delete_exchange(exchange)
      assert_raise Ecto.NoResultsError, fn -> Exchanges.get_exchange!(exchange.id) end
    end

    test "change_exchange/1 returns a changeset" do
      assert %Ecto.Changeset{} = Exchanges.change_exchange(exchange_fixture())
    end
  end
end

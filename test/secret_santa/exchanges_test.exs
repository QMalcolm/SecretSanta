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

    test "list_exchanges/0 fills in participant_count" do
      exchange = exchange_fixture()
      participant_fixture(exchange)
      participant_fixture(exchange)
      empty = exchange_fixture()

      counts = Map.new(Exchanges.list_exchanges(), &{&1.id, &1.participant_count})
      assert counts == %{exchange.id => 2, empty.id => 0}
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

    test "clone_exchange/2 copies participants and exclusions into a fresh open exchange" do
      source = exchange_fixture(name: "Family 2025")
      alice = participant_fixture(source, name: "Alice", email: "alice@example.com")
      bob = participant_fixture(source, name: "Bob", email: "bob@example.com")
      participant_fixture(source, name: "Carol", email: "carol@example.com")
      {:ok, _} = Exchanges.add_exclusion(source, alice, bob)
      {:ok, source} = Exchanges.draw_exchange(source)

      assert {:ok, %Exchange{} = clone} = Exchanges.clone_exchange(source, %{name: "Family 2026"})

      assert clone.name == "Family 2026"
      assert Exchange.open?(clone)
      refute clone.id == source.id

      participants = Exchanges.list_participants(clone)

      assert Enum.map(participants, &{&1.name, &1.email}) ==
               [
                 {"Alice", "alice@example.com"},
                 {"Bob", "bob@example.com"},
                 {"Carol", "carol@example.com"}
               ]

      assert Enum.all?(participants, &(&1.recipient_id == nil and &1.last_sent_at == nil))
      assert Enum.all?(participants, &(&1.exchange_id == clone.id))

      [new_alice, new_bob, _] = participants
      assert [%{giver_id: g, excluded_id: e}] = Exchanges.list_exclusions(clone)
      assert {g, e} == {new_alice.id, new_bob.id}

      # Source untouched.
      assert length(Exchanges.list_participants(source)) == 3
      assert length(Exchanges.list_exclusions(source)) == 1
    end

    test "clone_exchange/2 with an invalid name creates nothing" do
      source = exchange_fixture()
      participant_fixture(source)

      assert {:error, %Ecto.Changeset{}} = Exchanges.clone_exchange(source, %{name: ""})
      assert length(Exchanges.list_exchanges()) == 1
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

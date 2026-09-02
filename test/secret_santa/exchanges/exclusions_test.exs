defmodule SecretSanta.Exchanges.ExclusionsTest do
  use SecretSanta.DataCase, async: true

  import SecretSanta.ExchangesFixtures

  alias SecretSanta.Exchanges
  alias SecretSanta.Exchanges.Exclusion

  setup do
    exchange = exchange_fixture()
    alice = participant_fixture(exchange, name: "Alice")
    bob = participant_fixture(exchange, name: "Bob")
    %{exchange: exchange, alice: alice, bob: bob}
  end

  describe "add_exclusion/3" do
    test "records that giver must not draw excluded", ctx do
      assert {:ok, %Exclusion{} = x} = Exchanges.add_exclusion(ctx.exchange, ctx.alice, ctx.bob)
      assert x.exchange_id == ctx.exchange.id
      assert x.giver_id == ctx.alice.id
      assert x.excluded_id == ctx.bob.id
    end

    test "is one-directional", ctx do
      {:ok, _} = Exchanges.add_exclusion(ctx.exchange, ctx.alice, ctx.bob)

      assert [%{giver_id: giver, excluded_id: excluded}] = Exchanges.list_exclusions(ctx.exchange)
      assert {giver, excluded} == {ctx.alice.id, ctx.bob.id}

      assert {:ok, _} = Exchanges.add_exclusion(ctx.exchange, ctx.bob, ctx.alice)
      assert length(Exchanges.list_exclusions(ctx.exchange)) == 2
    end

    test "rejects excluding oneself", ctx do
      assert {:error, changeset} = Exchanges.add_exclusion(ctx.exchange, ctx.alice, ctx.alice)
      assert %{excluded_id: ["cannot be the giver themselves"]} = errors_on(changeset)
    end

    test "rejects a duplicate", ctx do
      {:ok, _} = Exchanges.add_exclusion(ctx.exchange, ctx.alice, ctx.bob)
      assert {:error, changeset} = Exchanges.add_exclusion(ctx.exchange, ctx.alice, ctx.bob)
      assert %{excluded_id: ["is already excluded for this giver"]} = errors_on(changeset)
    end

    test "rejects participants from another exchange", ctx do
      stranger = participant_fixture(exchange_fixture())

      assert {:error, :not_in_exchange} =
               Exchanges.add_exclusion(ctx.exchange, ctx.alice, stranger)

      assert {:error, :not_in_exchange} =
               Exchanges.add_exclusion(ctx.exchange, stranger, ctx.alice)
    end

    test "refuses once the exchange is drawn", ctx do
      drawn = draw!(ctx.exchange)
      assert {:error, :exchange_drawn} = Exchanges.add_exclusion(drawn, ctx.alice, ctx.bob)
    end
  end

  describe "remove_exclusion/3" do
    test "removes an existing exclusion", ctx do
      {:ok, _} = Exchanges.add_exclusion(ctx.exchange, ctx.alice, ctx.bob)
      assert {:ok, %Exclusion{}} = Exchanges.remove_exclusion(ctx.exchange, ctx.alice, ctx.bob)
      assert Exchanges.list_exclusions(ctx.exchange) == []
    end

    test "returns not_found when there is nothing to remove", ctx do
      assert {:error, :not_found} = Exchanges.remove_exclusion(ctx.exchange, ctx.alice, ctx.bob)
    end

    test "refuses once the exchange is drawn", ctx do
      {:ok, _} = Exchanges.add_exclusion(ctx.exchange, ctx.alice, ctx.bob)
      drawn = draw!(ctx.exchange)
      assert {:error, :exchange_drawn} = Exchanges.remove_exclusion(drawn, ctx.alice, ctx.bob)
    end
  end

  describe "list_exclusions/1" do
    test "returns only that exchange's exclusions", ctx do
      other = exchange_fixture()

      {:ok, _} =
        Exchanges.add_exclusion(other, participant_fixture(other), participant_fixture(other))

      {:ok, mine} = Exchanges.add_exclusion(ctx.exchange, ctx.alice, ctx.bob)

      assert Enum.map(Exchanges.list_exclusions(ctx.exchange), & &1.id) == [mine.id]
    end
  end

  describe "cascades" do
    test "deleting a participant removes exclusions in either role", ctx do
      carol = participant_fixture(ctx.exchange, name: "Carol")
      {:ok, _} = Exchanges.add_exclusion(ctx.exchange, ctx.alice, ctx.bob)
      {:ok, _} = Exchanges.add_exclusion(ctx.exchange, carol, ctx.alice)
      {:ok, kept} = Exchanges.add_exclusion(ctx.exchange, ctx.bob, carol)

      {:ok, _} = Exchanges.delete_participant(ctx.alice)

      assert Enum.map(Exchanges.list_exclusions(ctx.exchange), & &1.id) == [kept.id]
    end

    test "deleting the exchange removes its exclusions", ctx do
      {:ok, x} = Exchanges.add_exclusion(ctx.exchange, ctx.alice, ctx.bob)
      {:ok, _} = Exchanges.delete_exchange(ctx.exchange)
      assert Repo.get(Exclusion, x.id) == nil
    end
  end

  defp draw!(exchange) do
    exchange
    |> Ecto.Changeset.change(drawn_at: DateTime.utc_now(:second))
    |> Repo.update!()
  end
end

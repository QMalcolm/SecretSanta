defmodule SecretSanta.Exchanges.DrawTest do
  use SecretSanta.DataCase, async: true

  import SecretSanta.ExchangesFixtures

  alias SecretSanta.Exchanges

  defp group(exchange, names) do
    Map.new(names, fn name -> {name, participant_fixture(exchange, name: name)} end)
  end

  describe "legal_recipients/2" do
    test "excludes self and explicit exclusions, one-directionally" do
      exchange = exchange_fixture()
      %{"A" => a, "B" => b, "C" => c} = group(exchange, ~w(A B C))
      {:ok, _} = Exchanges.add_exclusion(exchange, a, b)

      legal = Exchanges.legal_recipients([a, b, c], Exchanges.list_exclusions(exchange))

      assert Enum.sort(legal[a.id]) == [c.id]
      assert Enum.sort(legal[b.id]) == Enum.sort([a.id, c.id])
      assert Enum.sort(legal[c.id]) == Enum.sort([a.id, b.id])
    end
  end

  describe "draw_blockers/1" do
    test "is empty for a drawable exchange" do
      exchange = exchange_fixture()
      group(exchange, ~w(A B C))
      assert Exchanges.draw_blockers(exchange) == []
    end

    test "reports too few participants with the count" do
      exchange = exchange_fixture()
      group(exchange, ~w(A B))
      assert [{:too_few_participants, 2}] = Exchanges.draw_blockers(exchange)
    end

    test "reports each participant with no legal recipient, alphabetically" do
      exchange = exchange_fixture()
      %{"A" => a, "B" => b, "C" => c} = group(exchange, ~w(A B C))
      {:ok, _} = Exchanges.add_exclusion(exchange, c, a)
      {:ok, _} = Exchanges.add_exclusion(exchange, c, b)
      {:ok, _} = Exchanges.add_exclusion(exchange, a, b)
      {:ok, _} = Exchanges.add_exclusion(exchange, a, c)

      assert [{:no_legal_recipient, %{id: a_id}}, {:no_legal_recipient, %{id: c_id}}] =
               Exchanges.draw_blockers(exchange)

      assert {a_id, c_id} == {a.id, c.id}
    end

    test "reports a drawn exchange first" do
      exchange = drawn_exchange_fixture()
      assert [:exchange_drawn, {:too_few_participants, 0}] = Exchanges.draw_blockers(exchange)
    end
  end

  describe "draw_exchange/1" do
    test "assigns everyone a distinct recipient, honoring exclusions, and stamps drawn_at" do
      exchange = exchange_fixture()
      %{"A" => a, "B" => b} = group(exchange, ~w(A B C D E))
      {:ok, _} = Exchanges.add_exclusion(exchange, a, b)
      {:ok, _} = Exchanges.add_exclusion(exchange, b, a)

      assert {:ok, drawn} = Exchanges.draw_exchange(exchange)
      assert %DateTime{} = drawn.drawn_at
      refute Exchanges.get_exchange!(exchange.id).drawn_at == nil

      participants = Exchanges.list_participants(exchange)
      ids = Enum.map(participants, & &1.id)
      recipients = Enum.map(participants, & &1.recipient_id)

      assert Enum.sort(recipients) == Enum.sort(ids)
      refute Enum.any?(participants, &(&1.id == &1.recipient_id))

      by_id = Map.new(participants, &{&1.id, &1})
      refute by_id[a.id].recipient_id == b.id
      refute by_id[b.id].recipient_id == a.id
    end

    test "refuses a second draw" do
      exchange = exchange_fixture()
      group(exchange, ~w(A B C))
      {:ok, drawn} = Exchanges.draw_exchange(exchange)

      assert {:error, :exchange_drawn} = Exchanges.draw_exchange(drawn)
      # Even with a stale struct that still looks open:
      assert {:error, :exchange_drawn} = Exchanges.draw_exchange(exchange)
    end

    test "refuses with too few participants and writes nothing" do
      exchange = exchange_fixture()
      group(exchange, ~w(A B))

      assert {:error, {:too_few_participants, 2}} = Exchanges.draw_exchange(exchange)
      assert Exchanges.get_exchange!(exchange.id).drawn_at == nil
    end

    test "refuses when someone has no legal recipient" do
      exchange = exchange_fixture()
      %{"A" => a, "B" => b, "C" => c} = group(exchange, ~w(A B C))
      {:ok, _} = Exchanges.add_exclusion(exchange, a, b)
      {:ok, _} = Exchanges.add_exclusion(exchange, a, c)

      assert {:error, {:no_legal_recipient, %{id: id}}} = Exchanges.draw_exchange(exchange)
      assert id == a.id
    end

    test "reports the participants involved when infeasibility is not obvious" do
      exchange = exchange_fixture()
      %{"A" => a, "B" => b, "C" => c} = group(exchange, ~w(A B C))
      # A and B can each only draw C; every individual has a legal recipient.
      {:ok, _} = Exchanges.add_exclusion(exchange, a, b)
      {:ok, _} = Exchanges.add_exclusion(exchange, b, a)

      assert Exchanges.draw_blockers(exchange) == []
      assert {:error, {:no_valid_assignment, [stuck]}} = Exchanges.draw_exchange(exchange)
      assert stuck.id in [a.id, b.id]
      assert c.recipient_id == nil
      assert Enum.all?(Exchanges.list_participants(exchange), &(&1.recipient_id == nil))
      assert Exchanges.get_exchange!(exchange.id).drawn_at == nil
    end
  end
end

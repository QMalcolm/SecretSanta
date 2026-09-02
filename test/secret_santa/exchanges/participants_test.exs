defmodule SecretSanta.Exchanges.ParticipantsTest do
  use SecretSanta.DataCase, async: true

  import SecretSanta.ExchangesFixtures

  alias SecretSanta.Exchanges
  alias SecretSanta.Exchanges.Participant

  setup do
    %{exchange: exchange_fixture()}
  end

  describe "list_participants/1" do
    test "returns only that exchange's participants, alphabetically", %{exchange: exchange} do
      other = exchange_fixture()
      participant_fixture(other, name: "Aaron")
      zed = participant_fixture(exchange, name: "Zed")
      amy = participant_fixture(exchange, name: "Amy")

      assert Enum.map(Exchanges.list_participants(exchange), & &1.id) == [amy.id, zed.id]
    end
  end

  describe "get_participant!/2" do
    test "returns the participant when it belongs to the exchange", %{exchange: exchange} do
      participant = participant_fixture(exchange)
      assert Exchanges.get_participant!(exchange, participant.id).id == participant.id
    end

    test "raises when the participant belongs to another exchange", %{exchange: exchange} do
      participant = participant_fixture(exchange_fixture())

      assert_raise Ecto.NoResultsError, fn ->
        Exchanges.get_participant!(exchange, participant.id)
      end
    end
  end

  describe "create_participant/2" do
    test "adds a participant with no recipient or send history", %{exchange: exchange} do
      assert {:ok, %Participant{} = p} =
               Exchanges.create_participant(exchange, %{name: "Alice", email: "alice@example.com"})

      assert p.exchange_id == exchange.id
      assert p.recipient_id == nil
      assert p.last_sent_at == nil
      assert p.last_error == nil
    end

    test "trims the name and normalizes the email", %{exchange: exchange} do
      assert {:ok, p} =
               Exchanges.create_participant(exchange, %{
                 name: "  Alice ",
                 email: " Alice@Example.COM "
               })

      assert p.name == "Alice"
      assert p.email == "alice@example.com"
    end

    test "requires name and email", %{exchange: exchange} do
      assert {:error, changeset} = Exchanges.create_participant(exchange, %{name: "", email: ""})
      assert %{name: ["can't be blank"], email: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects an email that does not look like one", %{exchange: exchange} do
      assert {:error, changeset} =
               Exchanges.create_participant(exchange, %{name: "Alice", email: "not an email"})

      assert %{email: [_]} = errors_on(changeset)
    end

    test "rejects a duplicate name within the exchange", %{exchange: exchange} do
      participant_fixture(exchange, name: "Alice")

      assert {:error, changeset} =
               Exchanges.create_participant(exchange, %{name: "Alice", email: "a2@example.com"})

      assert %{name: ["is already in this exchange"]} = errors_on(changeset)
    end

    test "rejects a duplicate email within the exchange, ignoring case", %{exchange: exchange} do
      participant_fixture(exchange, email: "alice@example.com")

      assert {:error, changeset} =
               Exchanges.create_participant(exchange, %{name: "Al", email: "ALICE@example.com"})

      assert %{email: ["is already in this exchange"]} = errors_on(changeset)
    end

    test "allows the same person in a different exchange", %{exchange: exchange} do
      participant_fixture(exchange, name: "Alice", email: "alice@example.com")

      assert {:ok, _} =
               Exchanges.create_participant(exchange_fixture(), %{
                 name: "Alice",
                 email: "alice@example.com"
               })
    end

    test "refuses once the exchange is drawn" do
      exchange = drawn_exchange_fixture()

      assert {:error, :exchange_drawn} =
               Exchanges.create_participant(exchange, %{name: "Late", email: "late@example.com"})
    end
  end

  describe "update_participant/2" do
    test "changes name and email", %{exchange: exchange} do
      participant = participant_fixture(exchange)

      assert {:ok, updated} =
               Exchanges.update_participant(participant, %{name: "Bob", email: "bob@example.com"})

      assert updated.name == "Bob"
      assert updated.email == "bob@example.com"
    end

    test "refuses once the exchange is drawn", %{exchange: exchange} do
      participant = participant_fixture(exchange)
      draw!(exchange)

      assert {:error, :exchange_drawn} = Exchanges.update_participant(participant, %{name: "Bob"})
    end
  end

  describe "delete_participant/1" do
    test "removes the participant", %{exchange: exchange} do
      participant = participant_fixture(exchange)
      assert {:ok, _} = Exchanges.delete_participant(participant)
      assert Exchanges.list_participants(exchange) == []
    end

    test "refuses once the exchange is drawn", %{exchange: exchange} do
      participant = participant_fixture(exchange)
      draw!(exchange)

      assert {:error, :exchange_drawn} = Exchanges.delete_participant(participant)
    end
  end

  test "deleting the exchange deletes its participants", %{exchange: exchange} do
    participant = participant_fixture(exchange)
    {:ok, _} = Exchanges.delete_exchange(exchange)
    assert Repo.get(Participant, participant.id) == nil
  end

  defp draw!(exchange) do
    exchange
    |> Ecto.Changeset.change(drawn_at: DateTime.utc_now(:second))
    |> Repo.update!()
  end
end

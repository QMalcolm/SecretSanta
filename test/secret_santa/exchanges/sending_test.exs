defmodule SecretSanta.Exchanges.SendingTest do
  # Not async: the failure tests swap the mailer adapter in application config.
  use SecretSanta.DataCase

  import Swoosh.TestAssertions
  import SecretSanta.ExchangesFixtures

  alias SecretSanta.Exchanges

  setup do
    exchange = exchange_fixture(name: "Family 2026")
    alice = participant_fixture(exchange, name: "Alice", email: "alice@example.com")
    participant_fixture(exchange, name: "Bob")
    participant_fixture(exchange, name: "Carol")
    %{exchange: exchange, alice: alice}
  end

  describe "send_assignment/1" do
    test "refuses before the draw", %{alice: alice} do
      assert {:error, :exchange_not_drawn} = Exchanges.send_assignment(alice)
      assert_no_email_sent()
    end

    test "emails the recipient's name and records the send", %{exchange: exchange, alice: alice} do
      {:ok, _} = Exchanges.draw_exchange(exchange)
      recipient_name = recipient_name(exchange, alice)

      assert {:ok, sent} = Exchanges.send_assignment(alice)

      assert %DateTime{} = sent.last_sent_at
      assert sent.last_error == nil

      assert_email_sent(fn email ->
        assert email.to == [{"Alice", "alice@example.com"}]
        assert email.subject == "Secret Santa: Family 2026"
        assert email.text_body =~ "you drew: #{recipient_name}."
      end)
    end

    test "always sends again, even if already sent", %{exchange: exchange, alice: alice} do
      {:ok, _} = Exchanges.draw_exchange(exchange)
      {:ok, _} = Exchanges.send_assignment(alice)
      {:ok, _} = Exchanges.send_assignment(alice)

      assert_email_sent(to: {"Alice", "alice@example.com"})
      assert_email_sent(to: {"Alice", "alice@example.com"})
    end

    test "records a failure without marking the row sent", %{exchange: exchange, alice: alice} do
      {:ok, _} = Exchanges.draw_exchange(exchange)
      use_failing_adapter()

      assert {:error, failed} = Exchanges.send_assignment(alice)

      assert failed.last_sent_at == nil
      assert failed.last_error =~ "econnrefused"
      assert_no_email_sent()
    end

    test "a later success clears the recorded failure", %{exchange: exchange, alice: alice} do
      {:ok, _} = Exchanges.draw_exchange(exchange)
      use_failing_adapter()
      {:error, _} = Exchanges.send_assignment(alice)
      restore_adapter()

      assert {:ok, sent} = Exchanges.send_assignment(alice)
      assert sent.last_error == nil
      assert %DateTime{} = sent.last_sent_at
    end
  end

  describe "unsent_participants/1" do
    test "lists those never successfully sent, alphabetically", %{
      exchange: exchange,
      alice: alice
    } do
      {:ok, _} = Exchanges.draw_exchange(exchange)
      {:ok, _} = Exchanges.send_assignment(alice)

      assert Enum.map(Exchanges.unsent_participants(exchange), & &1.name) == ["Bob", "Carol"]
    end

    test "still lists someone whose send failed", %{exchange: exchange, alice: alice} do
      {:ok, _} = Exchanges.draw_exchange(exchange)
      use_failing_adapter()
      {:error, _} = Exchanges.send_assignment(alice)

      assert "Alice" in Enum.map(Exchanges.unsent_participants(exchange), & &1.name)
    end
  end

  defp recipient_name(exchange, giver) do
    participants = Exchanges.list_participants(exchange)
    giver = Enum.find(participants, &(&1.id == giver.id))
    Enum.find(participants, &(&1.id == giver.recipient_id)).name
  end

  defp use_failing_adapter do
    original = Application.get_env(:secret_santa, SecretSanta.Mailer)

    Application.put_env(:secret_santa, SecretSanta.Mailer,
      adapter: SecretSanta.FailingMailAdapter
    )

    on_exit(fn -> Application.put_env(:secret_santa, SecretSanta.Mailer, original) end)
  end

  defp restore_adapter do
    Application.put_env(:secret_santa, SecretSanta.Mailer, adapter: Swoosh.Adapters.Test)
  end
end

defmodule SecretSanta.Exchanges.AssignmentEmailTest do
  use ExUnit.Case, async: true

  alias SecretSanta.Exchanges.{AssignmentEmail, Exchange, Participant}

  test "addresses the giver, names the exchange and the recipient, and nothing else" do
    exchange = %Exchange{name: "Family 2026"}
    alice = %Participant{name: "Alice", email: "alice@example.com"}
    bob = %Participant{name: "Bob", email: "bob@example.com"}

    email = AssignmentEmail.build(exchange, alice, bob)

    assert email.to == [{"Alice", "alice@example.com"}]
    assert email.from == {"", "secret-santa@localhost"}
    assert email.subject == "Secret Santa: Family 2026"
    assert email.text_body =~ "Hi Alice,"
    assert email.text_body =~ "For Family 2026, you drew: Bob."
    refute email.text_body =~ "bob@example.com"
    assert email.html_body == nil
  end
end

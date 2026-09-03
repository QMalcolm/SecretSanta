defmodule SecretSanta.Exchanges.AssignmentEmail do
  @moduledoc """
  Builds the one email this app sends: telling a participant who they
  drew (spec.md §4.6). Plain text, nothing but the recipient's name.
  """

  import Swoosh.Email

  alias SecretSanta.Exchanges.{Exchange, Participant}

  @doc "The email to `giver` telling them they drew `recipient`."
  def build(%Exchange{} = exchange, %Participant{} = giver, %Participant{} = recipient) do
    new()
    |> from(from_address())
    |> to({giver.name, giver.email})
    |> subject("Secret Santa: #{exchange.name}")
    |> text_body("""
    Hi #{giver.name},

    For #{exchange.name}, you drew: #{recipient.name}.

    Keep it secret!
    """)
  end

  defp from_address do
    Application.fetch_env!(:secret_santa, :mail_from)
  end
end

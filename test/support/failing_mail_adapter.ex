defmodule SecretSanta.FailingMailAdapter do
  @moduledoc "A Swoosh adapter that refuses every email, for testing failure handling."

  use Swoosh.Adapter

  @impl true
  def deliver(_email, _config), do: {:error, {:network_failure, "127.0.0.1", :econnrefused}}
end

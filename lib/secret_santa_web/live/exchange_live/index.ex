defmodule SecretSantaWeb.ExchangeLive.Index do
  @moduledoc "The home page: every exchange, plus creating and deleting them (spec.md §4.1)."

  use SecretSantaWeb, :live_view

  alias SecretSanta.Exchanges
  alias SecretSanta.Exchanges.Exchange

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Exchanges")
     |> assign_new_form()
     |> load_exchanges()}
  end

  @impl true
  def handle_event("validate", %{"exchange" => params}, socket) do
    changeset = Exchanges.change_exchange(%Exchange{}, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"exchange" => params}, socket) do
    case Exchanges.create_exchange(params) do
      {:ok, exchange} ->
        {:noreply,
         socket
         |> put_flash(:info, "Created #{exchange.name}. Now add some people.")
         |> push_navigate(to: ~p"/exchanges/#{exchange}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    exchange = Exchanges.get_exchange!(id)
    {:ok, _} = Exchanges.delete_exchange(exchange)

    {:noreply,
     socket
     |> put_flash(:info, "Deleted #{exchange.name}.")
     |> load_exchanges()}
  end

  defp assign_new_form(socket) do
    assign(socket, :form, to_form(Exchanges.change_exchange(%Exchange{})))
  end

  defp load_exchanges(socket) do
    assign(socket, :exchanges, Exchanges.list_exchanges())
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Exchanges
        <:subtitle>Each exchange is one year's draw. Create one to start adding people.</:subtitle>
      </.header>

      <.form for={@form} id="new-exchange-form" phx-change="validate" phx-submit="save">
        <div class="flex items-end gap-2">
          <div class="flex-1">
            <.input field={@form[:name]} label="New exchange" placeholder="Family 2026" />
          </div>
          <.button variant="primary" phx-disable-with="Creating...">Create</.button>
        </div>
      </.form>

      <p :if={@exchanges == []} id="no-exchanges" class="text-base-content/60">
        No exchanges yet.
      </p>

      <.table :if={@exchanges != []} id="exchanges" rows={@exchanges} row_id={&"exchange-#{&1.id}"}>
        <:col :let={exchange} label="Name">
          <.link navigate={~p"/exchanges/#{exchange}"} class="link link-hover font-medium">
            {exchange.name}
          </.link>
        </:col>
        <:col :let={exchange} label="Participants">{exchange.participant_count}</:col>
        <:col :let={exchange} label="Status"><.status exchange={exchange} /></:col>
        <:action :let={exchange}>
          <.link
            phx-click="delete"
            phx-value-id={exchange.id}
            data-confirm={"Delete #{exchange.name} and everyone in it? This cannot be undone."}
            class="link link-error"
          >
            Delete
          </.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  attr :exchange, Exchange, required: true

  defp status(assigns) do
    ~H"""
    <span :if={Exchange.open?(@exchange)} class="badge badge-outline">Open</span>
    <span :if={!Exchange.open?(@exchange)} class="badge badge-success">
      Drawn {Calendar.strftime(@exchange.drawn_at, "%Y-%m-%d")}
    </span>
    """
  end
end

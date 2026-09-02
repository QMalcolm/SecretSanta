defmodule SecretSantaWeb.ExchangeLive.Show do
  @moduledoc """
  One exchange: its participants, exclusions, and draw (spec.md §4.2–§4.6).

  While the exchange is open everything is editable; once drawn the page
  becomes read-only apart from revealing and sending.
  """

  use SecretSantaWeb, :live_view

  alias SecretSanta.Exchanges
  alias SecretSanta.Exchanges.{Exchange, Participant}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    exchange = Exchanges.get_exchange!(id)

    {:ok,
     socket
     |> assign(:exchange, exchange)
     |> assign(:page_title, exchange.name)
     |> assign(:editing, nil)
     |> assign_participant_form(%Participant{})
     |> load_participants()}
  end

  ## Participants

  @impl true
  def handle_event("validate", %{"participant" => params}, socket) do
    base = socket.assigns.editing || %Participant{}
    changeset = Exchanges.change_participant(base, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"participant" => params}, socket) do
    %{exchange: exchange, editing: editing} = socket.assigns

    result =
      case editing do
        nil -> Exchanges.create_participant(exchange, params)
        %Participant{} = participant -> Exchanges.update_participant(participant, params)
      end

    case result do
      {:ok, participant} ->
        {:noreply,
         socket
         |> put_flash(:info, "Saved #{participant.name}.")
         |> assign(:editing, nil)
         |> assign_participant_form(%Participant{})
         |> load_participants()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, :exchange_drawn} ->
        {:noreply, refuse_drawn(socket)}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    participant = Exchanges.get_participant!(socket.assigns.exchange, id)

    {:noreply,
     socket
     |> assign(:editing, participant)
     |> assign_participant_form(participant)}
  end

  def handle_event("cancel-edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing, nil)
     |> assign_participant_form(%Participant{})}
  end

  def handle_event("delete-participant", %{"id" => id}, socket) do
    participant = Exchanges.get_participant!(socket.assigns.exchange, id)

    case Exchanges.delete_participant(participant) do
      {:ok, _} ->
        editing = socket.assigns.editing

        socket =
          if editing && editing.id == participant.id,
            do: socket |> assign(:editing, nil) |> assign_participant_form(%Participant{}),
            else: socket

        {:noreply,
         socket
         |> put_flash(:info, "Removed #{participant.name}.")
         |> load_participants()}

      {:error, :exchange_drawn} ->
        {:noreply, refuse_drawn(socket)}
    end
  end

  defp assign_participant_form(socket, %Participant{} = participant) do
    assign(socket, :form, to_form(Exchanges.change_participant(participant)))
  end

  defp load_participants(socket) do
    assign(socket, :participants, Exchanges.list_participants(socket.assigns.exchange))
  end

  # The exchange was drawn under us (another tab, say). Reload so the page
  # switches to its read-only state.
  defp refuse_drawn(socket) do
    socket
    |> put_flash(:error, "This exchange has already been drawn and can no longer be changed.")
    |> assign(:exchange, Exchanges.get_exchange!(socket.assigns.exchange.id))
    |> assign(:editing, nil)
    |> load_participants()
  end

  ## Rendering

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :open?, Exchange.open?(assigns.exchange))

    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@exchange.name}
        <:subtitle>
          <span :if={@open?} class="badge badge-outline">Open</span>
          <span :if={!@open?} class="badge badge-success">
            Drawn {Calendar.strftime(@exchange.drawn_at, "%Y-%m-%d")}
          </span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/"}>
            <.icon name="hero-arrow-left" class="size-4" /> All exchanges
          </.button>
        </:actions>
      </.header>

      <section id="participants" class="space-y-4">
        <h2 class="text-base font-semibold">Participants</h2>

        <p :if={@participants == []} id="no-participants" class="text-base-content/60">
          Nobody yet. Add at least {Exchanges.min_participants()} people to draw.
        </p>

        <.table
          :if={@participants != []}
          id="participants-table"
          rows={@participants}
          row_id={&"participant-#{&1.id}"}
        >
          <:col :let={p} label="Name">{p.name}</:col>
          <:col :let={p} label="Email">{p.email}</:col>
          <:action :let={p} :if={@open?}>
            <.link phx-click="edit" phx-value-id={p.id} class="link">Edit</.link>
            <.link
              phx-click="delete-participant"
              phx-value-id={p.id}
              data-confirm={"Remove #{p.name} from this exchange?"}
              class="link link-error"
            >
              Remove
            </.link>
          </:action>
        </.table>

        <.form
          :if={@open?}
          for={@form}
          id="participant-form"
          phx-change="validate"
          phx-submit="save"
          class="card bg-base-200 p-4"
        >
          <h3 class="font-medium mb-2">
            {if @editing, do: "Edit #{@editing.name}", else: "Add a participant"}
          </h3>
          <div class="grid gap-2 sm:grid-cols-2">
            <.input field={@form[:name]} label="Name" placeholder="Alice" />
            <.input field={@form[:email]} type="email" label="Email" placeholder="alice@example.com" />
          </div>
          <div class="flex gap-2 mt-2">
            <.button variant="primary" phx-disable-with="Saving...">
              {if @editing, do: "Save changes", else: "Add"}
            </.button>
            <.button :if={@editing} type="button" phx-click="cancel-edit">Cancel</.button>
          </div>
        </.form>
      </section>
    </Layouts.app>
    """
  end
end

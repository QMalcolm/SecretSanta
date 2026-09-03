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
     |> assign(:revealed, MapSet.new())
     |> assign(:send_queue, [])
     |> assign(:sending_now, nil)
     |> assign(:send_tally, nil)
     |> assign_participant_form(%Participant{})
     |> reload()}
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
         |> reload()}

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
         |> reload()}

      {:error, :exchange_drawn} ->
        {:noreply, refuse_drawn(socket)}
    end
  end

  def handle_event("toggle-exclusion", %{"giver" => giver_id, "excluded" => excluded_id}, socket) do
    %{exchange: exchange, participants: participants} = socket.assigns
    giver = find_participant!(participants, giver_id)
    excluded = find_participant!(participants, excluded_id)

    result =
      if excluded?(socket.assigns.exclusions, giver, excluded),
        do: Exchanges.remove_exclusion(exchange, giver, excluded),
        else: Exchanges.add_exclusion(exchange, giver, excluded)

    case result do
      {:ok, _} -> {:noreply, reload(socket)}
      {:error, :exchange_drawn} -> {:noreply, refuse_drawn(socket)}
      # Stale grid (someone removed a participant in another tab); a reload fixes it.
      {:error, _} -> {:noreply, reload(socket)}
    end
  end

  ## Draw and assignments

  def handle_event("draw", _params, socket) do
    case Exchanges.draw_exchange(socket.assigns.exchange) do
      {:ok, exchange} ->
        {:noreply,
         socket
         |> assign(:exchange, exchange)
         |> assign(:editing, nil)
         |> put_flash(:info, "Drawn! Everyone has a recipient.")
         |> reload()}

      {:error, {:no_valid_assignment, stuck}} ->
        names = stuck |> Enum.map(& &1.name) |> Enum.join(", ")

        {:noreply,
         socket
         |> put_flash(
           :error,
           "No valid draw exists with these exclusions. Nobody could be found for: #{names}. " <>
             "Loosen the exclusions and try again."
         )
         |> reload()}

      {:error, :exchange_drawn} ->
        {:noreply, refuse_drawn(socket)}

      {:error, blocker} ->
        {:noreply, socket |> put_flash(:error, describe(blocker)) |> reload()}
    end
  end

  def handle_event("toggle-reveal", %{"id" => id}, socket) do
    id = String.to_integer(id)
    revealed = socket.assigns.revealed

    revealed =
      if MapSet.member?(revealed, id),
        do: MapSet.delete(revealed, id),
        else: MapSet.put(revealed, id)

    {:noreply, assign(socket, :revealed, revealed)}
  end

  ## Sending

  def handle_event("send-all", _params, socket) do
    ids = socket.assigns.exchange |> Exchanges.unsent_participants() |> Enum.map(& &1.id)
    {:noreply, start_sending(socket, ids)}
  end

  def handle_event("send-one", %{"id" => id}, socket) do
    {:noreply, start_sending(socket, [String.to_integer(id)])}
  end

  # Sends go one at a time through the mailbox so the page re-renders
  # between them: :send_next marks a row as sending, then {:send, id}
  # actually delivers. A batch that is already running is left alone.
  defp start_sending(%{assigns: %{sending_now: nil}} = socket, ids) when ids != [] do
    send(self(), :send_next)
    assign(socket, send_queue: ids, send_tally: %{ok: 0, error: 0})
  end

  defp start_sending(socket, _ids), do: socket

  @impl true
  def handle_info(:send_next, socket) do
    case socket.assigns.send_queue do
      [] ->
        {:noreply, finish_sending(socket)}

      [id | rest] ->
        send(self(), {:send, id})
        {:noreply, assign(socket, send_queue: rest, sending_now: id)}
    end
  end

  def handle_info({:send, id}, socket) do
    participant = find_participant!(socket.assigns.participants, Integer.to_string(id))
    tally = socket.assigns.send_tally

    tally =
      case Exchanges.send_assignment(participant) do
        {:ok, _} -> %{tally | ok: tally.ok + 1}
        {:error, _} -> %{tally | error: tally.error + 1}
      end

    send(self(), :send_next)
    {:noreply, socket |> assign(send_tally: tally) |> reload()}
  end

  defp finish_sending(socket) do
    %{ok: ok, error: error} = socket.assigns.send_tally

    message =
      case {ok, error} do
        {ok, 0} -> "Sent #{ok} #{plural(ok, "email")}."
        {0, error} -> "#{error} #{plural(error, "email")} failed. See the status column."
        {ok, error} -> "Sent #{ok}, #{error} failed. See the status column."
      end

    socket
    |> put_flash(if(error == 0, do: :info, else: :error), message)
    |> assign(sending_now: nil, send_tally: nil)
  end

  defp plural(1, word), do: word
  defp plural(_, word), do: word <> "s"

  defp assign_participant_form(socket, %Participant{} = participant) do
    assign(socket, :form, to_form(Exchanges.change_participant(participant)))
  end

  ## Exclusions

  defp find_participant!(participants, id) do
    id = String.to_integer(id)
    Enum.find(participants, &(&1.id == id)) || raise Ecto.NoResultsError, queryable: Participant
  end

  defp excluded?(exclusions, giver, excluded) do
    Enum.any?(exclusions, &(&1.giver_id == giver.id and &1.excluded_id == excluded.id))
  end

  ## Loading

  # Participants, exclusions, and the draw blockers derived from them are
  # always loaded together: removing a participant cascades to exclusions,
  # and any change to either can change what blocks the draw.
  defp reload(socket) do
    exchange = socket.assigns.exchange
    participants = Exchanges.list_participants(exchange)
    exclusions = Exchanges.list_exclusions(exchange)

    assign(socket,
      participants: participants,
      exclusions: exclusions,
      blockers: Exchanges.draw_blockers(exchange, participants, exclusions)
    )
  end

  # The exchange was drawn under us (another tab, say). Reload so the page
  # switches to its read-only state.
  defp refuse_drawn(socket) do
    socket
    |> put_flash(:error, "This exchange has already been drawn and can no longer be changed.")
    |> assign(:exchange, Exchanges.get_exchange!(socket.assigns.exchange.id))
    |> assign(:editing, nil)
    |> reload()
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

      <section :if={length(@participants) >= 2} id="exclusions" class="space-y-4">
        <h2 class="text-base font-semibold">Exclusions</h2>
        <p class="text-sm text-base-content/70">
          Tick a box to stop the person in that row from drawing the person in that column.
          Exclusions are one-way: to stop both directions, tick both boxes.
        </p>

        <div class="overflow-x-auto">
          <table id="exclusions-grid" class="table table-sm">
            <thead>
              <tr>
                <th class="text-left">must not draw →</th>
                <th :for={p <- @participants} class="text-center whitespace-nowrap">{p.name}</th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={giver <- @participants}
                id={"exclusions-#{giver.id}"}
                class={stuck?(@blockers, giver) && "bg-error/10"}
              >
                <th class="text-left whitespace-nowrap font-medium">{giver.name}</th>
                <td :for={excluded <- @participants} class="text-center">
                  <span :if={giver.id == excluded.id} class="text-base-content/30">—</span>
                  <input
                    :if={giver.id != excluded.id}
                    type="checkbox"
                    id={"exclusion-#{giver.id}-#{excluded.id}"}
                    class="checkbox checkbox-sm"
                    checked={excluded?(@exclusions, giver, excluded)}
                    disabled={!@open?}
                    phx-click="toggle-exclusion"
                    phx-value-giver={giver.id}
                    phx-value-excluded={excluded.id}
                    aria-label={"#{giver.name} must not draw #{excluded.name}"}
                  />
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <section :if={@open?} id="draw" class="space-y-4">
        <h2 class="text-base font-semibold">Draw</h2>
        <.blockers blockers={@blockers} />
        <.button
          id="draw-button"
          variant="primary"
          phx-click="draw"
          disabled={@blockers != []}
          data-confirm="Draw now? Participants and exclusions will be locked and cannot be changed afterwards."
          phx-disable-with="Drawing..."
        >
          <.icon name="hero-gift" class="size-4" /> Draw
        </.button>
      </section>

      <section :if={!@open?} id="assignments" class="space-y-4">
        <div class="flex items-end justify-between gap-4">
          <div>
            <h2 class="text-base font-semibold">Assignments</h2>
            <p class="text-sm text-base-content/70">
              Hidden so you don't spoil your own draw. Reveal a row only if you need to.
              Each person gets one plain-text email naming who they drew.
            </p>
          </div>
          <.button
            id="send-all-button"
            variant="primary"
            phx-click="send-all"
            disabled={@sending_now != nil or unsent_count(@participants) == 0}
          >
            <.icon name="hero-paper-airplane" class="size-4" />
            {if @sending_now, do: "Sending…", else: "Send all (#{unsent_count(@participants)} unsent)"}
          </.button>
        </div>

        <.table id="assignments-table" rows={@participants} row_id={&"assignment-#{&1.id}"}>
          <:col :let={p} label="Giver">{p.name}</:col>
          <:col :let={p} label="Drew">
            <span :if={MapSet.member?(@revealed, p.id)} class="font-medium">
              {recipient_name(@participants, p)}
            </span>
            <span :if={!MapSet.member?(@revealed, p.id)} class="text-base-content/40 select-none">
              ••••••••
            </span>
          </:col>
          <:col :let={p} label="Email">
            <.send_status participant={p} sending={@sending_now == p.id} />
          </:col>
          <:action :let={p}>
            <.link phx-click="toggle-reveal" phx-value-id={p.id} class="link">
              {if MapSet.member?(@revealed, p.id), do: "Hide", else: "Reveal"}
            </.link>
            <.link
              :if={@sending_now == nil}
              phx-click="send-one"
              phx-value-id={p.id}
              data-confirm={"Email #{p.name} their assignment#{if p.last_sent_at, do: " again"}?"}
              class="link"
            >
              {if p.last_sent_at, do: "Resend", else: "Send"}
            </.link>
          </:action>
        </.table>
      </section>
    </Layouts.app>
    """
  end

  attr :blockers, :list, required: true

  defp blockers(assigns) do
    ~H"""
    <ul :if={@blockers != []} id="draw-blockers" class="space-y-1 text-sm">
      <li :for={blocker <- @blockers} class="flex items-center gap-2 text-warning">
        <.icon name="hero-exclamation-triangle" class="size-4 shrink-0" />
        <span>{describe(blocker)}</span>
      </li>
    </ul>
    <p :if={@blockers == []} id="draw-ready" class="text-sm text-success">
      <.icon name="hero-check-circle" class="size-4 inline" /> Everyone has someone they can draw.
    </p>
    """
  end

  defp describe(:exchange_drawn), do: "This exchange has already been drawn."

  defp describe({:too_few_participants, n}) do
    "Need at least #{Exchanges.min_participants()} participants to draw (have #{n})."
  end

  defp describe({:no_legal_recipient, %Participant{name: name}}) do
    "#{name} has nobody left they are allowed to draw."
  end

  attr :participant, Participant, required: true
  attr :sending, :boolean, required: true

  defp send_status(%{sending: true} = assigns) do
    ~H"""
    <span class="badge badge-info badge-sm">Sending…</span>
    """
  end

  defp send_status(%{participant: %Participant{last_sent_at: %DateTime{}}} = assigns) do
    ~H"""
    <span class="text-success text-sm whitespace-nowrap">
      Sent {Calendar.strftime(@participant.last_sent_at, "%Y-%m-%d %H:%M")}
    </span>
    """
  end

  defp send_status(%{participant: %Participant{last_error: error}} = assigns)
       when is_binary(error) do
    ~H"""
    <span class="text-error text-sm" title={@participant.last_error}>
      Failed: {String.slice(@participant.last_error, 0, 60)}
    </span>
    """
  end

  defp send_status(assigns) do
    ~H"""
    <span class="text-base-content/60 text-sm">Not sent</span>
    """
  end

  defp unsent_count(participants), do: Enum.count(participants, &is_nil(&1.last_sent_at))

  defp recipient_name(participants, %Participant{recipient_id: recipient_id}) do
    case Enum.find(participants, &(&1.id == recipient_id)) do
      %Participant{name: name} -> name
      nil -> "?"
    end
  end

  defp stuck?(blockers, %Participant{id: id}) do
    Enum.any?(blockers, &match?({:no_legal_recipient, %Participant{id: ^id}}, &1))
  end
end

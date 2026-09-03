defmodule SecretSantaWeb.ExchangeLive.ShowTest do
  use SecretSantaWeb.ConnCase

  import Phoenix.LiveViewTest
  import SecretSanta.ExchangesFixtures

  alias SecretSanta.Exchanges

  describe "participants on an open exchange" do
    setup do
      %{exchange: exchange_fixture(name: "Family 2026")}
    end

    test "renders the exchange and its participants", %{conn: conn, exchange: exchange} do
      alice = participant_fixture(exchange, name: "Alice", email: "alice@example.com")

      {:ok, view, html} = live(conn, ~p"/exchanges/#{exchange}")

      assert html =~ "Family 2026"
      assert html =~ "Open"
      assert view |> element("#participant-#{alice.id}") |> render() =~ "alice@example.com"
      assert has_element?(view, "#participant-form")
    end

    test "shows an empty state with the minimum group size", %{conn: conn, exchange: exchange} do
      {:ok, view, _html} = live(conn, ~p"/exchanges/#{exchange}")
      assert view |> element("#no-participants") |> render() =~ "at least 3"
    end

    test "adds a participant", %{conn: conn, exchange: exchange} do
      {:ok, view, _html} = live(conn, ~p"/exchanges/#{exchange}")

      html =
        view
        |> form("#participant-form", participant: %{name: "Bob", email: "bob@example.com"})
        |> render_submit()

      assert html =~ "Saved Bob."
      assert [%{name: "Bob", email: "bob@example.com"}] = Exchanges.list_participants(exchange)
      # Form resets for the next person.
      refute view |> element("#participant_name") |> render() =~ "Bob"
    end

    test "shows validation errors", %{conn: conn, exchange: exchange} do
      participant_fixture(exchange, name: "Bob")
      {:ok, view, _html} = live(conn, ~p"/exchanges/#{exchange}")

      html =
        view
        |> form("#participant-form", participant: %{name: "Bob", email: "bob2@example.com"})
        |> render_submit()

      assert html =~ "is already in this exchange"

      html =
        view
        |> form("#participant-form", participant: %{name: "Bobby", email: "nope"})
        |> render_submit()

      assert html =~ "must have the @ sign"
      assert length(Exchanges.list_participants(exchange)) == 1
    end

    test "edits a participant", %{conn: conn, exchange: exchange} do
      bob = participant_fixture(exchange, name: "Bob", email: "bob@example.com")
      {:ok, view, _html} = live(conn, ~p"/exchanges/#{exchange}")

      view |> element("#participant-#{bob.id} a", "Edit") |> render_click()
      assert render(view) =~ "Edit Bob"

      html =
        view
        |> form("#participant-form", participant: %{name: "Robert"})
        |> render_submit()

      assert html =~ "Saved Robert."
      assert Exchanges.get_participant!(exchange, bob.id).name == "Robert"
      assert render(view) =~ "Add a participant"
    end

    test "cancels an edit", %{conn: conn, exchange: exchange} do
      bob = participant_fixture(exchange, name: "Bob")
      {:ok, view, _html} = live(conn, ~p"/exchanges/#{exchange}")

      view |> element("#participant-#{bob.id} a", "Edit") |> render_click()
      view |> element("#participant-form button", "Cancel") |> render_click()

      assert render(view) =~ "Add a participant"
    end

    test "removes a participant", %{conn: conn, exchange: exchange} do
      bob = participant_fixture(exchange, name: "Bob")
      {:ok, view, _html} = live(conn, ~p"/exchanges/#{exchange}")

      view |> element("#participant-#{bob.id} a", "Remove") |> render_click()

      refute has_element?(view, "#participant-#{bob.id}")
      assert render(view) =~ "Removed Bob."
      assert Exchanges.list_participants(exchange) == []
    end

    test "switches to read-only if the exchange is drawn underneath it", %{
      conn: conn,
      exchange: exchange
    } do
      {:ok, view, _html} = live(conn, ~p"/exchanges/#{exchange}")

      drawn_exchange_fixture_from(exchange)

      html =
        view
        |> form("#participant-form", participant: %{name: "Late", email: "late@example.com"})
        |> render_submit()

      assert html =~ "already been drawn"
      refute has_element?(view, "#participant-form")
      assert Exchanges.list_participants(exchange) == []
    end
  end

  describe "exclusions" do
    setup do
      exchange = exchange_fixture()
      alice = participant_fixture(exchange, name: "Alice")
      bob = participant_fixture(exchange, name: "Bob")
      carol = participant_fixture(exchange, name: "Carol")
      %{exchange: exchange, alice: alice, bob: bob, carol: carol}
    end

    test "is hidden until there are two participants", %{conn: conn} do
      exchange = exchange_fixture()
      participant_fixture(exchange)
      {:ok, view, _html} = live(conn, ~p"/exchanges/#{exchange}")
      refute has_element?(view, "#exclusions")
    end

    test "renders a grid with no self cells", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/exchanges/#{ctx.exchange}")

      assert has_element?(view, "#exclusion-#{ctx.alice.id}-#{ctx.bob.id}")
      refute has_element?(view, "#exclusion-#{ctx.alice.id}-#{ctx.alice.id}")
      assert has_element?(view, "#draw-ready")
    end

    test "toggling a cell adds and then removes an exclusion, one-way", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/exchanges/#{ctx.exchange}")
      cell = "#exclusion-#{ctx.alice.id}-#{ctx.bob.id}"
      reverse = "#exclusion-#{ctx.bob.id}-#{ctx.alice.id}"

      view |> element(cell) |> render_click()
      assert has_element?(view, cell <> "[checked]")
      refute has_element?(view, reverse <> "[checked]")
      assert [%{giver_id: g, excluded_id: e}] = Exchanges.list_exclusions(ctx.exchange)
      assert {g, e} == {ctx.alice.id, ctx.bob.id}

      view |> element(cell) |> render_click()
      refute has_element?(view, cell <> "[checked]")
      assert Exchanges.list_exclusions(ctx.exchange) == []
    end

    test "warns live when someone has nobody left to draw", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/exchanges/#{ctx.exchange}")

      view |> element("#exclusion-#{ctx.alice.id}-#{ctx.bob.id}") |> render_click()
      refute has_element?(view, "#draw-blockers")

      view |> element("#exclusion-#{ctx.alice.id}-#{ctx.carol.id}") |> render_click()

      assert view |> element("#draw-blockers") |> render() =~ "Alice has nobody left"
      assert view |> element("#exclusions-#{ctx.alice.id}") |> render() =~ "bg-error/10"
      refute has_element?(view, "#draw-ready")
    end

    test "warns about too few participants", %{conn: conn} do
      exchange = exchange_fixture()
      participant_fixture(exchange)
      participant_fixture(exchange)
      {:ok, view, _html} = live(conn, ~p"/exchanges/#{exchange}")

      assert view |> element("#draw-blockers") |> render() =~ "at least 3 participants"
    end

    test "is disabled once drawn", ctx do
      {:ok, _} = Exchanges.add_exclusion(ctx.exchange, ctx.alice, ctx.bob)
      drawn_exchange_fixture_from(ctx.exchange)
      {:ok, view, _html} = live(ctx.conn, ~p"/exchanges/#{ctx.exchange}")

      cell = "#exclusion-#{ctx.alice.id}-#{ctx.bob.id}"
      assert has_element?(view, cell <> "[checked][disabled]")
      refute has_element?(view, "#draw")
    end
  end

  describe "drawing" do
    setup do
      exchange = exchange_fixture()
      alice = participant_fixture(exchange, name: "Alice")
      bob = participant_fixture(exchange, name: "Bob")
      carol = participant_fixture(exchange, name: "Carol")
      %{exchange: exchange, alice: alice, bob: bob, carol: carol}
    end

    test "the button is disabled while something blocks the draw", %{conn: conn} do
      exchange = exchange_fixture()
      participant_fixture(exchange)
      participant_fixture(exchange)
      {:ok, view, _html} = live(conn, ~p"/exchanges/#{exchange}")

      assert has_element?(view, "#draw-button[disabled]")
    end

    test "draws, locks the page, and masks assignments", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/exchanges/#{ctx.exchange}")
      refute has_element?(view, "#draw-button[disabled]")

      html = view |> element("#draw-button") |> render_click()

      assert html =~ "Drawn! Everyone has a recipient."
      assert html =~ "Drawn 20"
      refute has_element?(view, "#participant-form")
      refute has_element?(view, "#draw")
      assert has_element?(view, "#assignments")

      participants = Exchanges.list_participants(ctx.exchange)
      assert Enum.all?(participants, &(&1.recipient_id != nil))

      row = view |> element("#assignment-#{ctx.alice.id}") |> render()
      assert row =~ "••••"
      refute row =~ recipient_name(participants, ctx.alice)
    end

    test "reveals and hides one row at a time", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/exchanges/#{ctx.exchange}")
      view |> element("#draw-button") |> render_click()
      participants = Exchanges.list_participants(ctx.exchange)

      view |> element("#assignment-#{ctx.alice.id} a", "Reveal") |> render_click()

      assert view |> element("#assignment-#{ctx.alice.id}") |> render() =~
               recipient_name(participants, ctx.alice)

      assert view |> element("#assignment-#{ctx.bob.id}") |> render() =~ "••••"

      view |> element("#assignment-#{ctx.alice.id} a", "Hide") |> render_click()
      assert view |> element("#assignment-#{ctx.alice.id}") |> render() =~ "••••"
    end

    test "explains a non-obvious impossible draw and stays open", ctx do
      # Alice and Bob can each only draw Carol.
      {:ok, _} = Exchanges.add_exclusion(ctx.exchange, ctx.alice, ctx.bob)
      {:ok, _} = Exchanges.add_exclusion(ctx.exchange, ctx.bob, ctx.alice)
      {:ok, view, _html} = live(ctx.conn, ~p"/exchanges/#{ctx.exchange}")
      refute has_element?(view, "#draw-button[disabled]")

      html = view |> element("#draw-button") |> render_click()

      assert html =~ "No valid draw exists"
      assert html =~ ~r/Nobody could be found for: (Alice|Bob)\./
      assert has_element?(view, "#participant-form")
      assert Exchanges.get_exchange!(ctx.exchange.id).drawn_at == nil
    end

    test "a second draw from a stale tab is refused", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/exchanges/#{ctx.exchange}")
      {:ok, _} = Exchanges.draw_exchange(ctx.exchange)

      html = view |> element("#draw-button") |> render_click()

      assert html =~ "already been drawn"
      assert has_element?(view, "#assignments")
    end

    defp recipient_name(participants, giver) do
      giver = Enum.find(participants, &(&1.id == giver.id))
      Enum.find(participants, &(&1.id == giver.recipient_id)).name
    end
  end

  describe "sending" do
    import Swoosh.TestAssertions

    setup do
      # The Test adapter notifies the sending process, which here is the
      # LiveView; route notifications to the test instead.
      Application.put_env(:swoosh, :shared_test_process, self())
      on_exit(fn -> Application.delete_env(:swoosh, :shared_test_process) end)

      exchange = exchange_fixture(name: "Family 2026")
      alice = participant_fixture(exchange, name: "Alice", email: "alice@example.com")
      bob = participant_fixture(exchange, name: "Bob", email: "bob@example.com")
      carol = participant_fixture(exchange, name: "Carol", email: "carol@example.com")
      {:ok, exchange} = Exchanges.draw_exchange(exchange)
      %{exchange: exchange, alice: alice, bob: bob, carol: carol}
    end

    test "starts with everyone not sent", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/exchanges/#{ctx.exchange}")

      assert view |> element("#assignment-#{ctx.alice.id}") |> render() =~ "Not sent"
      assert view |> element("#send-all-button") |> render() =~ "Send all (3 unsent)"
      refute has_element?(view, "#send-all-button[disabled]")
    end

    test "send all emails everyone unsent and updates each row", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/exchanges/#{ctx.exchange}")

      view |> element("#send-all-button") |> render_click()
      html = wait_until_idle(view)

      assert_email_sent(to: {"Alice", "alice@example.com"})
      assert_email_sent(to: {"Bob", "bob@example.com"})
      assert_email_sent(to: {"Carol", "carol@example.com"})

      assert html =~ "Sent 3 emails."
      assert view |> element("#assignment-#{ctx.alice.id}") |> render() =~ "Sent 20"
      assert view |> element("#send-all-button") |> render() =~ "Send all (0 unsent)"
      assert has_element?(view, "#send-all-button[disabled]")
      assert Enum.all?(Exchanges.list_participants(ctx.exchange), &(&1.last_sent_at != nil))
    end

    test "send all skips people already sent", ctx do
      {:ok, _} = Exchanges.send_assignment(ctx.alice)
      assert_email_sent(to: {"Alice", "alice@example.com"})
      {:ok, view, _html} = live(ctx.conn, ~p"/exchanges/#{ctx.exchange}")

      assert view |> element("#send-all-button") |> render() =~ "Send all (2 unsent)"
      view |> element("#send-all-button") |> render_click()
      wait_until_idle(view)

      assert_email_sent(to: {"Bob", "bob@example.com"})
      assert_email_sent(to: {"Carol", "carol@example.com"})
      refute_email_sent(to: {"Alice", "alice@example.com"})
    end

    test "resend emails one person even if already sent", ctx do
      {:ok, _} = Exchanges.send_assignment(ctx.alice)
      assert_email_sent(to: {"Alice", "alice@example.com"})
      {:ok, view, _html} = live(ctx.conn, ~p"/exchanges/#{ctx.exchange}")

      assert view |> element("#assignment-#{ctx.alice.id} a", "Resend") |> render_click()
      html = wait_until_idle(view)

      assert html =~ "Sent 1 email."
      assert_email_sent(to: {"Alice", "alice@example.com"})
      refute_email_sent(to: {"Bob", "bob@example.com"})
    end

    test "a failed send shows on the row and stays unsent", ctx do
      original = Application.get_env(:secret_santa, SecretSanta.Mailer)

      Application.put_env(:secret_santa, SecretSanta.Mailer,
        adapter: SecretSanta.FailingMailAdapter
      )

      on_exit(fn -> Application.put_env(:secret_santa, SecretSanta.Mailer, original) end)

      {:ok, view, _html} = live(ctx.conn, ~p"/exchanges/#{ctx.exchange}")

      view |> element("#assignment-#{ctx.bob.id} a", "Send") |> render_click()
      html = wait_until_idle(view)

      assert html =~ "1 email failed."
      assert view |> element("#assignment-#{ctx.bob.id}") |> render() =~ "Failed: "
      assert view |> element("#assignment-#{ctx.bob.id}") |> render() =~ "econnrefused"
      assert view |> element("#send-all-button") |> render() =~ "Send all (3 unsent)"
      assert_no_email_sent()
    end

    # Sends are driven by messages the LiveView posts to itself, so the
    # click returns before the batch finishes.
    defp wait_until_idle(view, attempts \\ 50) do
      html = render(view)

      cond do
        not (html =~ "Sending…") and not (html =~ ~s(id="send-all-button" disabled)) ->
          html

        not (html =~ "Sending…") and html =~ "Send all (0 unsent)" ->
          html

        attempts == 0 ->
          flunk("sending never finished")

        true ->
          Process.sleep(10)
          wait_until_idle(view, attempts - 1)
      end
    end
  end

  describe "a drawn exchange" do
    test "is read-only", %{conn: conn} do
      exchange = drawn_exchange_fixture(name: "Work 2025")
      {:ok, view, html} = live(conn, ~p"/exchanges/#{exchange}")

      assert html =~ "Drawn"
      refute has_element?(view, "#participant-form")
    end
  end

  test "404s for an unknown exchange", %{conn: conn} do
    assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/exchanges/999999") end
  end

  defp drawn_exchange_fixture_from(exchange) do
    exchange
    |> Ecto.Changeset.change(drawn_at: DateTime.utc_now(:second))
    |> SecretSanta.Repo.update!()
  end
end

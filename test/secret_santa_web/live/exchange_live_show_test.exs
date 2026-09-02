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

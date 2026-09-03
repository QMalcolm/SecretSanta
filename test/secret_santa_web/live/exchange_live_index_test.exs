defmodule SecretSantaWeb.ExchangeLive.IndexTest do
  use SecretSantaWeb.ConnCase

  import Phoenix.LiveViewTest
  import SecretSanta.ExchangesFixtures

  test "lists exchanges with participant count and status", %{conn: conn} do
    open = exchange_fixture(name: "Family 2026")
    participant_fixture(open)
    drawn = drawn_exchange_fixture(name: "Work 2025")

    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "Family 2026"
    assert html =~ "Work 2025"
    assert view |> element("#exchange-#{open.id}") |> render() =~ "Open"
    assert view |> element("#exchange-#{drawn.id}") |> render() =~ "Drawn"
    assert view |> element("#exchange-#{open.id} td", "1") |> has_element?()
    assert has_element?(view, ~s|#exchange-#{open.id} a[href="/exchanges/#{open.id}"]|)
  end

  test "shows an empty state", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#no-exchanges")
  end

  test "creates an exchange", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#new-exchange-form", exchange: %{name: "Family 2026"})
    |> render_submit()

    assert [%{name: "Family 2026"} = exchange] = SecretSanta.Exchanges.list_exchanges()
    assert_redirect(view, ~p"/exchanges/#{exchange}")
  end

  test "shows validation errors", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html =
      view
      |> form("#new-exchange-form", exchange: %{name: ""})
      |> render_submit()

    assert html =~ "can&#39;t be blank"
    assert SecretSanta.Exchanges.list_exchanges() == []
  end

  test "deletes an exchange", %{conn: conn} do
    exchange = exchange_fixture(name: "Old one")
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#exchange-#{exchange.id} a", "Delete")
    |> render_click()

    refute has_element?(view, "#exchange-#{exchange.id}")
    assert render(view) =~ "Deleted Old one."
    assert SecretSanta.Exchanges.list_exchanges() == []
  end

  describe "new from previous" do
    test "clones the chosen exchange under a new name", %{conn: conn} do
      source = exchange_fixture(name: "Family 2025")
      alice = participant_fixture(source, name: "Alice")
      bob = participant_fixture(source, name: "Bob")
      {:ok, _} = SecretSanta.Exchanges.add_exclusion(source, alice, bob)

      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#exchange-#{source.id} a", "New from this") |> render_click()
      assert render(view) =~ "New exchange from Family 2025"
      assert has_element?(view, "#clone-hint")

      view
      |> form("#new-exchange-form", exchange: %{name: "Family 2026"})
      |> render_submit()

      assert [%{name: "Family 2026"} = clone, %{name: "Family 2025"}] =
               SecretSanta.Exchanges.list_exchanges()

      assert clone.participant_count == 2
      assert length(SecretSanta.Exchanges.list_exclusions(clone)) == 1
      assert_redirect(view, ~p"/exchanges/#{clone}")
    end

    test "can be cancelled back to a plain new exchange", %{conn: conn} do
      source = exchange_fixture(name: "Family 2025")
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#exchange-#{source.id} a", "New from this") |> render_click()
      view |> element("#cancel-clone") |> render_click()

      refute render(view) =~ "New exchange from"
      refute has_element?(view, "#clone-hint")
    end
  end
end

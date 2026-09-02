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
  end

  test "shows an empty state", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#no-exchanges")
  end

  test "creates an exchange", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html =
      view
      |> form("#new-exchange-form", exchange: %{name: "Family 2026"})
      |> render_submit()

    assert html =~ "Family 2026"
    assert html =~ "Created Family 2026."
    assert [%{name: "Family 2026"}] = SecretSanta.Exchanges.list_exchanges()
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
end

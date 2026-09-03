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
    test "opens a modal with a prefilled name and clones on submit", %{conn: conn} do
      source = exchange_fixture(name: "Family 2025")
      alice = participant_fixture(source, name: "Alice")
      bob = participant_fixture(source, name: "Bob")
      {:ok, _} = SecretSanta.Exchanges.add_exclusion(source, alice, bob)

      {:ok, view, _html} = live(conn, ~p"/")
      refute has_element?(view, "#clone-modal")

      view |> element("#exchange-#{source.id} a", "New from this") |> render_click()

      assert has_element?(view, "#clone-modal")
      assert view |> element("#clone-modal h3") |> render() =~ "New exchange from Family 2025"

      assert has_element?(
               view,
               ~s|#clone-form input[name="exchange[name]"][value="Family 2025 Copy"]|
             )

      view
      |> form("#clone-form", exchange: %{name: "Family 2026"})
      |> render_submit()

      assert [%{name: "Family 2026"} = clone, %{name: "Family 2025"}] =
               SecretSanta.Exchanges.list_exchanges()

      assert clone.participant_count == 2
      assert length(SecretSanta.Exchanges.list_exclusions(clone)) == 1
      assert_redirect(view, ~p"/exchanges/#{clone}")
    end

    test "shows validation errors inside the modal", %{conn: conn} do
      source = exchange_fixture(name: "Family 2025")
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#exchange-#{source.id} a", "New from this") |> render_click()

      html =
        view
        |> form("#clone-form", exchange: %{name: ""})
        |> render_submit()

      assert has_element?(view, "#clone-modal")
      assert html =~ "can&#39;t be blank"
      assert length(SecretSanta.Exchanges.list_exchanges()) == 1
    end

    test "cancel closes the modal without creating anything", %{conn: conn} do
      source = exchange_fixture(name: "Family 2025")
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#exchange-#{source.id} a", "New from this") |> render_click()
      view |> element("#clone-modal button", "Cancel") |> render_click()

      refute has_element?(view, "#clone-modal")
      assert length(SecretSanta.Exchanges.list_exchanges()) == 1
    end
  end
end

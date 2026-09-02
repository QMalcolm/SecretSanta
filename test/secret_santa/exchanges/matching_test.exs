defmodule SecretSanta.Exchanges.MatchingTest do
  use ExUnit.Case, async: true

  alias SecretSanta.Exchanges.Matching

  defp complete(ids), do: Map.new(ids, fn id -> {id, ids -- [id]} end)

  describe "perfect_matching/1" do
    test "assigns everyone exactly once on an unconstrained group" do
      ids = Enum.to_list(1..6)
      assert {:ok, assignment} = Matching.perfect_matching(complete(ids))

      assert Enum.sort(Map.keys(assignment)) == ids
      assert Enum.sort(Map.values(assignment)) == ids
      refute Enum.any?(assignment, fn {g, r} -> g == r end)
    end

    test "only uses listed candidates" do
      candidates = %{a: [:b], b: [:c], c: [:a]}
      assert {:ok, %{a: :b, b: :c, c: :a}} = Matching.perfect_matching(candidates)
    end

    test "allows a two-person swap" do
      assert {:ok, %{a: :b, b: :a}} = Matching.perfect_matching(%{a: [:b], b: [:a]})
    end

    test "finds the assignment when the obvious greedy choice would fail" do
      # If :a takes :c first, :b is stuck; the augmenting path must move :a to :b.
      candidates = %{a: [:c, :b], b: [:c], c: [:a]}
      assert {:ok, %{a: :b, b: :c, c: :a}} = Matching.perfect_matching(candidates)
    end

    test "reports the givers left over when no perfect matching exists" do
      # :a and :b can only draw :c, so exactly one of them will be unmatched.
      candidates = %{a: [:c], b: [:c], c: [:a, :b]}
      assert {:error, [unmatched]} = Matching.perfect_matching(candidates)
      assert unmatched in [:a, :b]
    end

    test "reports a giver with no candidates at all" do
      candidates = %{a: [], b: [:a], c: [:b]}
      assert {:error, unmatched} = Matching.perfect_matching(candidates)
      assert :a in unmatched
    end

    test "handles the empty group" do
      assert {:ok, %{}} = Matching.perfect_matching(%{})
    end

    test "is random" do
      candidates = complete(Enum.to_list(1..5))

      distinct =
        1..50
        |> Enum.map(fn _ ->
          {:ok, a} = Matching.perfect_matching(candidates)
          a
        end)
        |> Enum.uniq()
        |> length()

      assert distinct > 1
    end
  end
end

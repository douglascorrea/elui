defmodule Elui.FuzzyTest do
  use ExUnit.Case, async: true

  alias Elui.Fuzzy

  test "characters in order, smart case, words all match, best first" do
    e = Fuzzy.prepare(["lib/vibex/client.ex", "lib/vibex/cli.ex", "README.md", "VibexCore"])
    assert [{0, _}, {1, _}] = Fuzzy.filter("clie", e)
    assert [{1, [10, 11, 12]}, {0, _}] = Fuzzy.filter("cli", e)
    # A capital letter makes the match case-sensitive.
    assert [{3, [0, 5]}] = Fuzzy.filter("VC", e)
    assert Fuzzy.filter("vc", e) |> Enum.map(&elem(&1, 0)) |> Enum.member?(3)
    # Every word must match, anywhere.
    assert [{1, _}] = Fuzzy.filter("cli lib", Fuzzy.prepare(["x", "lib/cli", "cli"]))
    assert Fuzzy.filter("zz", e) == []
    # No query: everything, in order.
    assert Enum.map(Fuzzy.filter("", e), &elem(&1, 0)) == [0, 1, 2, 3]
    assert Fuzzy.match?("vbx", "vibex") and not Fuzzy.match?("xv", "vibex")
  end

  test "a growing query refines the previous matches" do
    e = Fuzzy.prepare(["alpha", "alps", "beta"])
    first = Fuzzy.filter("al", e)
    assert Fuzzy.refine("alp", "al", first, e) == Fuzzy.filter("alp", e)
    assert Fuzzy.refine("b", "al", first, e) == Fuzzy.filter("b", e)
  end

  test "a word start and a match at the start rank higher than one inside a word" do
    e = Fuzzy.prepare(["unrelated", "release 0.8", "the-release"])
    assert [{1, _}, {2, _}, {0, _}] = Fuzzy.filter("rel", e)
  end
end

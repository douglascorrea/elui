defmodule Elui.Text.WrapTest do
  use ExUnit.Case, async: true

  alias Elui.Style
  alias Elui.Text.{Span, Wrap}

  defp lines(spans, width, trim \\ false) do
    spans
    |> Wrap.spans(width, trim)
    |> Enum.map(fn spans -> Enum.map_join(spans, & &1.content) end)
  end

  test "breaks at spaces and drops them at line ends" do
    assert lines([Span.raw("one two  three")], 7) == ["one two", "three"]
  end

  test "keeps a span's style on its graphemes across lines" do
    red = Style.new(fg: :red)

    assert Wrap.spans([Span.raw("a "), Span.new("bc de", red)], 4) == [
             [Span.raw("a "), Span.new("bc", red)],
             [Span.new("de", red)]
           ]
  end

  test "trim drops the spaces opening the first line; spaces wider than the line go anyway" do
    assert lines([Span.raw("  ab")], 4) == ["  ab"]
    assert lines([Span.raw("  ab")], 4, true) == ["ab"]
    assert lines([Span.raw("     ab")], 4) == ["ab"]
  end

  test "cuts words wider than the line, by display width" do
    assert lines([Span.raw("abcdefg h")], 3) == ["abc", "def", "g h"]
    assert lines([Span.raw("日本語")], 3) == ["日", "本", "語"]
    assert lines([Span.raw("")], 3) == [""]
  end

  test "chop/2 cuts text without wrapping it" do
    assert Wrap.chop("ab cd ef", 3) == ["ab ", "cd ", "ef"]
    assert Wrap.chop("", 3) == [""]
  end
end

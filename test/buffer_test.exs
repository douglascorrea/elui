defmodule Elui.BufferTest do
  use ExUnit.Case, async: true

  alias Elui.Buffer
  alias Elui.Buffer.Cell
  alias Elui.Layout.Rect
  alias Elui.Style
  alias Elui.Text.Line

  test "set_string writes and clips" do
    buffer = Buffer.empty(Rect.new(0, 0, 5, 1))
    buffer = Buffer.set_string(buffer, 0, 0, "Hello World")
    assert Buffer.to_lines(buffer) == ["Hello"]
  end

  test "set_string applies style" do
    buffer = Buffer.empty(Rect.new(0, 0, 5, 1))
    buffer = Buffer.set_string(buffer, 0, 0, "Hi", fg: :red)
    assert Buffer.get(buffer, 0, 0).style.fg == :red
    assert Buffer.get(buffer, 1, 0).style.fg == :red
  end

  test "set_line honors alignment" do
    buffer = Buffer.empty(Rect.new(0, 0, 10, 1))
    line = Line.new("ab", alignment: :right)
    {buffer, _} = Buffer.set_line(buffer, 0, 0, line, 10)
    assert Buffer.to_lines(buffer) == ["        ab"]
  end

  test "set_style patches an area" do
    buffer = Buffer.empty(Rect.new(0, 0, 3, 1))
    buffer = Buffer.set_string(buffer, 0, 0, "abc")
    buffer = Buffer.set_style(buffer, Rect.new(0, 0, 2, 1), Style.new(fg: :blue))
    assert Buffer.get(buffer, 0, 0).style.fg == :blue
    assert Buffer.get(buffer, 2, 0).style.fg == nil
  end

  test "diff returns only changed cells" do
    area = Rect.new(0, 0, 5, 1)
    a = Buffer.set_string(Buffer.empty(area), 0, 0, "aaaaa")
    b = Buffer.set_string(Buffer.empty(area), 0, 0, "aabaa")

    assert [{2, 0, %Cell{symbol: "b"}}] = Buffer.diff(a, b)
  end

  test "wide graphemes occupy two cells" do
    buffer = Buffer.empty(Rect.new(0, 0, 4, 1))
    buffer = Buffer.set_string(buffer, 0, 0, "你a")
    assert Buffer.get(buffer, 0, 0).symbol == "你"
    assert Buffer.get(buffer, 1, 0).skip
    assert Buffer.get(buffer, 2, 0).symbol == "a"
  end

  test "writes outside the area are ignored" do
    buffer = Buffer.empty(Rect.new(0, 0, 2, 2))
    buffer = Buffer.put(buffer, 5, 5, Cell.new("x"))
    assert buffer.cells == %{}
  end
end

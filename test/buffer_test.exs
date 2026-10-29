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

  test "set_string preserves inherited cell attributes that its style does not override" do
    area = Rect.new(0, 0, 5, 1)

    buffer =
      area
      |> Buffer.empty()
      |> Buffer.set_style(area, bg: :white, add_modifier: [:bold])
      |> Buffer.set_string(0, 0, "Hi", fg: :red)

    cell = Buffer.get(buffer, 0, 0)

    assert cell.symbol == "H"
    assert cell.style.fg == :red
    assert cell.style.bg == :white
    assert :bold in cell.style.add_modifier
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

  # A buffer with a mix of unset cells, shared styles, modifiers and a wide
  # grapheme's skipped trailing cell.
  defp sample_buffer(seed) do
    :rand.seed(:exsss, {seed, seed, seed})
    area = Rect.new(2, 1, 9, 5)

    styles = [
      Style.new(),
      Style.new(fg: :red),
      Style.new(bg: :blue, add_modifier: [:bold]),
      Style.new(sub_modifier: [:italic]),
      Style.reset()
    ]

    buffer =
      for {x, y} <- Rect.positions(area), :rand.uniform(4) > 1, reduce: Buffer.empty(area) do
        buffer ->
          cell = Cell.new(Enum.random(["a", "b", " "]), Enum.random(styles))
          Buffer.put(buffer, x, y, cell)
      end

    Buffer.set_string(buffer, 3, 2, "界", fg: :green)
  end

  test "set_style gives the same cells as patching each cell in turn" do
    reference = fn buffer, area, style ->
      style = Style.to_style(style)

      cells =
        buffer.area
        |> Rect.intersection(area)
        |> Rect.positions()
        |> Enum.reduce(buffer.cells, fn pos, cells ->
          cell = Map.get(cells, pos, Cell.empty())
          Map.put(cells, pos, Cell.set_style(cell, style))
        end)

      %{buffer | cells: cells}
    end

    patches = [
      [],
      Style.new(),
      [fg: :yellow],
      [bg: :black, add_modifier: [:italic]],
      [sub_modifier: [:bold]],
      Style.reset()
    ]

    areas = [
      Rect.new(0, 0, 20, 20),
      Rect.new(4, 2, 3, 2),
      Rect.new(10, 5, 4, 4),
      Rect.new(30, 30, 2, 2)
    ]

    for seed <- 1..5, patch <- patches, area <- areas do
      buffer = sample_buffer(seed)

      assert Buffer.set_style(buffer, area, patch) == reference.(buffer, area, patch),
             "seed #{seed}, #{inspect(patch)} over #{inspect(area)}"
    end
  end

  test "diff lists the same updates, in the same order, as comparing every cell" do
    reference = fn previous, next ->
      next.area
      |> Rect.positions()
      |> Enum.flat_map(fn {x, y} ->
        prev_cell = Buffer.get(previous, x, y)
        next_cell = Buffer.get(next, x, y)
        if prev_cell == next_cell or next_cell.skip, do: [], else: [{x, y, next_cell}]
      end)
    end

    for a <- 1..4, b <- 1..4 do
      previous = sample_buffer(a)
      next = sample_buffer(b)
      updates = Buffer.diff(previous, next)

      assert updates == reference.(previous, next)
      assert a == b == (updates == [])
    end

    empty = Buffer.empty(Rect.new(0, 0, 0, 3))
    assert Buffer.diff(empty, empty) == []
  end
end

defmodule Elui.Mermaid.Grid do
  @moduledoc false

  # A sparse grid of cells that diagrams are drawn into. A line cell keeps
  # the directions it joins (up, right, down, left) and is drawn as the
  # box-drawing character for them, so junctions and crossings come out
  # right in whatever order the lines are drawn. Text replaces what is
  # under it.

  import Bitwise

  alias Elui.Style
  alias Elui.Text.{Line, Span, Width}

  @up 1
  @right 2
  @down 4
  @left 8

  defstruct cells: %{}, ascii: false

  @type t :: %__MODULE__{}
  @type point :: {integer(), integer()}

  # Weights in the order a crossing keeps: the heavier line wins.
  @weights %{dotted: 0, light: 1, double: 2, heavy: 3}

  @light %{
    5 => "│",
    10 => "─",
    6 => "┌",
    12 => "┐",
    3 => "└",
    9 => "┘",
    7 => "├",
    13 => "┤",
    14 => "┬",
    11 => "┴",
    15 => "┼"
  }

  @heavy %{
    5 => "┃",
    10 => "━",
    6 => "┏",
    12 => "┓",
    3 => "┗",
    9 => "┛",
    7 => "┣",
    13 => "┫",
    14 => "┳",
    11 => "┻",
    15 => "╋"
  }

  @double %{
    5 => "║",
    10 => "═",
    6 => "╔",
    12 => "╗",
    3 => "╚",
    9 => "╝",
    7 => "╠",
    13 => "╣",
    14 => "╦",
    11 => "╩",
    15 => "╬"
  }

  @rounded %{6 => "╭", 12 => "╮", 3 => "╰", 9 => "╯"}

  @arrows %{up: "▲", down: "▼", left: "◄", right: "►"}
  @ascii_arrows %{up: "^", down: "v", left: "<", right: ">"}

  @spec new(Keyword.t()) :: t()
  def new(opts \\ []), do: %__MODULE__{ascii: Keyword.get(opts, :ascii, false)}

  @doc """
  Draws a line through `points`, each one in line with the one before.
  Options: `:weight` (`:light`, `:heavy`, `:double` or `:dotted`),
  `:role` (a key of the styles `to_lines/2` gets), `:round` for rounded
  corners, and `:over`, the roles of lines it replaces instead of joining
  them (an edge crossing a subgraph's border). Text stays on top.
  """
  @spec line(t(), [point()], Keyword.t()) :: t()
  def line(grid, points, opts \\ [])
  def line(grid, [], _opts), do: grid

  def line(grid, points, opts), do: trace(grid, cells(points), opts)

  @doc "Every cell a line through `points` passes, in order."
  @spec cells([point()]) :: [point()]
  def cells([]), do: []
  def cells(points), do: path(points)

  @doc "Draws a line through `cells`, each next to the one before; `opts` as for `line/3`."
  @spec trace(t(), [point()], Keyword.t()) :: t()
  def trace(grid, cells, opts), do: line_cells(grid, cells, opts)

  @doc "Draws the outline of a box; `opts` as for `line/3`."
  @spec box(t(), integer(), integer(), pos_integer(), pos_integer(), Keyword.t()) :: t()
  def box(grid, x, y, w, h, opts \\ []) do
    right = x + w - 1
    bottom = y + h - 1
    line(grid, [{x, y}, {right, y}, {right, bottom}, {x, bottom}, {x, y}], opts)
  end

  @doc """
  Shows `glyph` in a line cell for as long as nothing else joins it: a
  shape's slanted corner or curved side, which turns into a junction
  when an edge meets it.
  """
  @spec shape(t(), point(), String.t()) :: t()
  def shape(grid, point, glyph) do
    case grid.cells do
      %{^point => {:line, bits, weight, round, role, _glyph}} ->
        put(grid, point, {:line, bits, weight, round, role, {glyph, bits}})

      _ ->
        grid
    end
  end

  @doc "An arrowhead at `point` pointing `direction`."
  @spec arrow(t(), point(), :up | :down | :left | :right, atom()) :: t()
  def arrow(grid, point, direction, role) do
    glyph = if grid.ascii, do: @ascii_arrows[direction], else: @arrows[direction]
    put(grid, point, {:text, glyph, role, nil})
  end

  @doc "A single character at `point`, replacing what is there."
  @spec mark(t(), point(), String.t(), atom()) :: t()
  def mark(grid, point, glyph, role), do: put(grid, point, {:text, glyph, role, nil})

  @doc """
  Writes spans from `{x, y}` to the right, replacing what is under them.
  A wide character takes two cells.
  """
  @spec text(t(), point(), [Span.t()], atom()) :: t()
  def text(grid, {x, y}, spans, role) do
    {grid, _x} =
      spans
      |> Enum.flat_map(fn span ->
        span.content |> String.graphemes() |> Enum.map(&{&1, span.style})
      end)
      |> Enum.reduce({grid, x}, fn {grapheme, style}, {grid, x} ->
        case Width.grapheme_width(grapheme) do
          0 ->
            {grid, x}

          2 ->
            grid = grid |> put({x, y}, {:text, grapheme, role, style}) |> put({x + 1, y}, :wide)
            {grid, x + 2}

          _ ->
            {put(grid, {x, y}, {:text, grapheme, role, style}), x + 1}
        end
      end)

    grid
  end

  @doc "The role of what is drawn at `point`, or `nil`."
  @spec role(t(), point()) :: atom() | nil
  def role(grid, point) do
    case Map.get(grid.cells, point) do
      {:line, _bits, _weight, _round, role, _glyph} -> role
      {:text, _glyph, role, _style} -> role
      _other -> nil
    end
  end

  @doc """
  The grid as lines, from row 0 and column 0 to the last drawn cell, with
  `styles` (role => `Elui.Style`) for each cell's role.
  """
  @spec to_lines(t(), %{atom() => Style.t()}) :: [Line.t()]
  def to_lines(%__MODULE__{cells: cells}, _styles) when map_size(cells) == 0, do: []

  def to_lines(grid, styles) do
    rows =
      Enum.group_by(grid.cells, fn {{_x, y}, _cell} -> y end, fn {{x, _y}, cell} -> {x, cell} end)

    last = rows |> Map.keys() |> Enum.max()

    for y <- 0..last//1 do
      cells = rows |> Map.get(y, []) |> Map.new()

      width =
        if map_size(cells) == 0, do: 0, else: cells |> Map.keys() |> Enum.max() |> Kernel.+(1)

      spans =
        0..(width - 1)//1
        |> Enum.flat_map(fn x ->
          case Map.get(cells, x) do
            nil -> [{" ", nil}]
            :wide -> []
            cell -> [glyph(grid, cell, styles)]
          end
        end)
        |> Enum.chunk_by(fn {_glyph, style} -> style end)
        |> Enum.map(fn chunk ->
          {_glyph, style} = hd(chunk)
          content = Enum.map_join(chunk, fn {glyph, _style} -> glyph end)
          if style, do: Span.new(content, style), else: Span.raw(content)
        end)

      %Line{spans: spans}
    end
  end

  # -- lines --------------------------------------------------------------------------------

  # Every cell a path through corner points passes, in order.
  defp path([point]), do: [point]

  defp path([from, to | rest]) do
    [_ | tail] = path([to | rest])
    steps(from, to) ++ tail
  end

  defp steps({x, y1}, {x, y2}), do: Enum.map(y1..y2//sign(y2 - y1), &{x, &1})
  defp steps({x1, y}, {x2, y}), do: Enum.map(x1..x2//sign(x2 - x1), &{&1, y})

  defp sign(0), do: 1
  defp sign(n) when n > 0, do: 1
  defp sign(_n), do: -1

  defp line_cells(grid, cells, opts) do
    weight = Keyword.get(opts, :weight, :light)
    role = Keyword.get(opts, :role, :edge)
    round = Keyword.get(opts, :round, false)
    over = Keyword.get(opts, :over, [])

    [cells, [nil | cells], Enum.drop(cells, 1) ++ [nil]]
    |> Enum.zip()
    |> Enum.reduce(grid, fn {cell, before, next}, grid ->
      bits = direction(cell, before) ||| direction(cell, next)
      join(grid, cell, bits, weight, round, role, over)
    end)
  end

  defp direction(_cell, nil), do: 0
  defp direction({x, y}, {x, y2}) when y2 < y, do: @up
  defp direction({x, y}, {x, y2}) when y2 > y, do: @down
  defp direction({x, y}, {x2, y}) when x2 > x, do: @right
  defp direction({x, y}, {x2, y}) when x2 < x, do: @left
  defp direction(_cell, _other), do: 0

  defp join(grid, point, bits, weight, round, role, over) do
    case Map.get(grid.cells, point) do
      nil ->
        put(grid, point, {:line, bits, weight, round, role, nil})

      {:line, old, old_weight, old_round, old_role, glyph} ->
        if old_role in over do
          put(grid, point, {:line, bits, weight, round, role, nil})
        else
          weight = if @weights[weight] > @weights[old_weight], do: weight, else: old_weight
          put(grid, point, {:line, old ||| bits, weight, old_round or round, old_role, glyph})
        end

      _text ->
        grid
    end
  end

  defp put(grid, point, cell), do: %{grid | cells: Map.put(grid.cells, point, cell)}

  # -- glyphs -------------------------------------------------------------------------------

  defp glyph(_grid, {:text, glyph, role, style}, styles),
    do: {glyph, Style.patch(Map.get(styles, role, %Style{}), style)}

  defp glyph(grid, {:line, bits, weight, round, role, override}, styles) do
    glyph =
      case override do
        {glyph, ^bits} -> glyph
        _ -> line_glyph(grid.ascii, bits, weight, round)
      end

    {glyph, Map.get(styles, role, %Style{})}
  end

  # A line's end joins nothing on one side; it draws as a whole line.
  defp line_glyph(ascii, bits, weight, round) when bits in [@up, @down],
    do: line_glyph(ascii, @up ||| @down, weight, round)

  defp line_glyph(ascii, bits, weight, round) when bits in [@left, @right],
    do: line_glyph(ascii, @left ||| @right, weight, round)

  defp line_glyph(true, bits, weight, _round) do
    case {bits, weight} do
      {5, :dotted} -> ":"
      {10, :dotted} -> "."
      {10, weight} when weight in [:heavy, :double] -> "="
      {5, _weight} -> "|"
      {10, _weight} -> "-"
      _ -> "+"
    end
  end

  defp line_glyph(false, bits, :dotted, round) do
    case bits do
      5 -> "┆"
      10 -> "┄"
      _ -> line_glyph(false, bits, :light, round)
    end
  end

  defp line_glyph(false, bits, :heavy, _round), do: Map.get(@heavy, bits, " ")
  defp line_glyph(false, bits, :double, _round), do: Map.get(@double, bits, " ")

  defp line_glyph(false, bits, :light, round) do
    (round && Map.get(@rounded, bits)) || Map.get(@light, bits, " ")
  end
end

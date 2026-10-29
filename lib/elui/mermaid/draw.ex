defmodule Elui.Mermaid.Draw do
  @moduledoc false

  # Draws a flowchart laid out by `Elui.Mermaid.Layout` into a grid:
  # subgraph boxes first, then the nodes, the edges (which join a node's
  # border where they meet it and cross a subgraph's), and the edges'
  # labels on top.

  alias Elui.Mermaid.Grid
  alias Elui.Text.{Span, Width}

  @spec flowchart(map(), Keyword.t()) :: Grid.t()
  def flowchart(geometry, opts \\ []) do
    ascii = Keyword.get(opts, :ascii, false)
    grid = Grid.new(ascii: ascii)

    grid =
      Enum.reduce(geometry.clusters, grid, fn cluster, grid ->
        Grid.box(grid, cluster.x, cluster.y, cluster.w, cluster.h, round: true, role: :cluster)
      end)

    grid = Enum.reduce(geometry.nodes, grid, &node(&2, &1, ascii))

    grid =
      geometry.edges
      |> Enum.reject(&(&1.edge.line == :invisible))
      |> Enum.reduce(grid, fn %{edge: edge, points: points}, grid ->
        marks = if edge.reversed, do: {edge.head, edge.tail}, else: {edge.tail, edge.head}
        edge_line(grid, Grid.cells(points), edge.line, marks, ascii)
      end)

    grid = Enum.reduce(geometry.loops, grid, &loop(&2, &1, geometry.direction, ascii))
    grid = Enum.reduce(geometry.clusters, grid, &title(&2, &1))
    Enum.reduce(geometry.labels, grid, &edge_label(&2, &1, geometry.vertical))
  end

  # -- subgraphs ----------------------------------------------------------------------------

  # A subgraph's title in its top border, as far left as it goes without
  # covering an edge that crosses the border.
  defp title(grid, cluster) do
    room = cluster.w - 6

    title =
      cluster.title
      |> Enum.intersperse([Span.raw(" ")])
      |> Enum.concat()
      |> truncate(room)

    if title == [] or room < 1 do
      grid
    else
      spans = [Span.raw(" ") | title] ++ [Span.raw(" ")]
      width = spans |> Enum.map(&Span.width/1) |> Enum.sum()
      last = cluster.x + cluster.w - 2 - width

      x =
        Enum.find(
          (cluster.x + 2)..last//1,
          cluster.x + 2,
          fn x ->
            Enum.all?(x..(x + width - 1)//1, &(Grid.role(grid, {&1, cluster.y}) == :cluster))
          end
        )

      Grid.text(grid, {x, cluster.y}, spans, :cluster_title)
    end
  end

  # -- nodes --------------------------------------------------------------------------------

  defp node(grid, %{node: node, x: x, y: y, w: w, h: h, lines: lines}, ascii) do
    shape = node.shape
    weight = if shape == :double_circle, do: :double, else: :light
    round = shape in [:round, :stadium, :circle, :cylinder]
    right = x + w - 1
    bottom = y + h - 1

    grid =
      grid
      |> Grid.box(x, y, w, h, weight: weight, round: round, role: :node)
      |> shape(shape, x, y, right, bottom, ascii)

    top = if shape == :cylinder, do: y + 2, else: y + 1
    room = if shape == :cylinder, do: h - 3, else: h - 2
    first = top + div(room - length(lines), 2)

    lines
    |> Enum.with_index()
    |> Enum.reduce(grid, fn {spans, i}, grid ->
      width = spans |> Enum.map(&Span.width/1) |> Enum.sum()
      Grid.text(grid, {x + div(w - width, 2), first + i}, spans, :label)
    end)
  end

  defp shape(grid, :subroutine, x, y, right, bottom, _ascii) do
    grid
    |> Grid.line([{x + 1, y}, {x + 1, bottom}], role: :node)
    |> Grid.line([{right - 1, y}, {right - 1, bottom}], role: :node)
  end

  defp shape(grid, :cylinder, x, y, right, _bottom, _ascii),
    do: Grid.line(grid, [{x, y + 1}, {right, y + 1}], role: :node, round: true)

  defp shape(grid, kind, x, y, right, bottom, ascii) when kind in [:rhombus, :hexagon] do
    {rising, falling} = if ascii, do: {"/", "\\"}, else: {"╱", "╲"}

    grid
    |> Grid.shape({x, y}, rising)
    |> Grid.shape({right, y}, falling)
    |> Grid.shape({x, bottom}, falling)
    |> Grid.shape({right, bottom}, rising)
  end

  defp shape(grid, :stadium, x, y, right, bottom, _ascii),
    do: sides(grid, x, y, right, bottom, "(", ")")

  defp shape(grid, :asymmetric, x, y, right, bottom, _ascii),
    do: sides(grid, x, y, right, bottom, ">", nil)

  defp shape(grid, kind, x, y, right, bottom, ascii)
       when kind in [:lean_right, :lean_left, :trapezoid, :inv_trapezoid] do
    {rising, falling} = if ascii, do: {"/", "\\"}, else: {"╱", "╲"}

    {left, right_side} =
      case kind do
        :lean_right -> {rising, rising}
        :lean_left -> {falling, falling}
        :trapezoid -> {rising, falling}
        :inv_trapezoid -> {falling, rising}
      end

    sides(grid, x, y, right, bottom, left, right_side)
  end

  defp shape(grid, _shape, _x, _y, _right, _bottom, _ascii), do: grid

  defp sides(grid, x, y, right, bottom, left, right_glyph) do
    Enum.reduce((y + 1)..(bottom - 1)//1, grid, fn row, grid ->
      grid = if left, do: Grid.shape(grid, {x, row}, left), else: grid
      if right_glyph, do: Grid.shape(grid, {right, row}, right_glyph), else: grid
    end)
  end

  # -- edges --------------------------------------------------------------------------------

  # A line from the first cell to the last, each on a node's border; an
  # end with a mark draws it on the cell beside the border instead.
  defp edge_line(grid, cells, line, {start_mark, end_mark}, ascii) do
    {cells, grid_marks} =
      {cells, []}
      |> mark_end(end_mark, :last)
      |> mark_end(start_mark, :first)

    weight =
      case line do
        :thick -> :heavy
        :dotted -> :dotted
        _ -> :light
      end

    grid = Grid.trace(grid, cells, weight: weight, role: :edge, round: true, over: [:cluster])

    Enum.reduce(grid_marks, grid, fn {mark, point, direction}, grid ->
      case mark do
        :arrow -> Grid.arrow(grid, point, direction, :edge)
        :cross -> Grid.mark(grid, point, if(ascii, do: "x", else: "×"), :edge)
        :circle -> Grid.mark(grid, point, if(ascii, do: "o", else: "○"), :edge)
      end
    end)
  end

  defp mark_end({cells, marks}, nil, _which), do: {cells, marks}

  defp mark_end({cells, marks}, mark, :last) when length(cells) >= 3 do
    cells = Enum.drop(cells, -1)
    [point, before | _] = Enum.reverse(cells)
    {cells, [{mark, point, direction(before, point)} | marks]}
  end

  defp mark_end({cells, marks}, mark, :first) when length(cells) >= 3 do
    [_border, point, next | _] = cells
    {tl(cells), [{mark, point, direction(next, point)} | marks]}
  end

  defp mark_end(acc, _mark, _which), do: acc

  defp direction({x, y1}, {x, y2}) when y2 > y1, do: :down
  defp direction({x, _y1}, {x, _y2}), do: :up
  defp direction({x1, _y}, {x2, _y2}) when x2 > x1, do: :right
  defp direction(_from, _to), do: :left

  # A loop from a node back to itself, on the side away from the edges.
  # The loop's label goes beside it up and down the page, and under it,
  # within the box's width, sideways.
  defp loop(grid, %{edge: edge, points: points, label: label}, direction, ascii) do
    cells = Grid.cells(points)
    grid = edge_line(grid, cells, edge.line, {edge.tail, edge.head}, ascii)
    {xs, ys} = Enum.unzip(cells)

    case label do
      nil ->
        grid

      [spans] ->
        width = spans |> Enum.map(&Span.width/1) |> Enum.sum()

        point =
          case direction do
            vertical when vertical in [:tb, :bt] -> {Enum.max(xs) + 2, ys |> hd()}
            :lr -> {Enum.min(xs), Enum.max(ys) + 1}
            :rl -> {Enum.max(xs) - width + 1, Enum.max(ys) + 1}
          end

        Grid.text(grid, point, spans, :edge_label)
    end
  end

  # An edge's label, on its line, with a space either side.
  defp edge_label(grid, %{lines: lines, x: x, y: y, w: w}, vertical) do
    top = if vertical, do: y + 1, else: y

    lines
    |> Enum.with_index()
    |> Enum.reduce(grid, fn {spans, i}, grid ->
      width = spans |> Enum.map(&Span.width/1) |> Enum.sum()
      left = x + div(w - width, 2)

      Grid.text(
        grid,
        {left - 1, top + i},
        [Span.raw(" ") | spans] ++ [Span.raw(" ")],
        :edge_label
      )
    end)
  end

  # Spans cut to `width` columns, with an ellipsis when they are cut.
  defp truncate(spans, width) do
    total = spans |> Enum.map(&Span.width/1) |> Enum.sum()

    if total <= width do
      spans
    else
      {kept, _room} =
        Enum.reduce(spans, {[], width - 1}, fn span, {kept, room} ->
          {text, used} =
            span.content
            |> String.graphemes()
            |> Enum.reduce_while({"", 0}, fn grapheme, {text, used} ->
              w = Width.grapheme_width(grapheme)

              if used + w <= room,
                do: {:cont, {text <> grapheme, used + w}},
                else: {:halt, {text, used}}
            end)

          {[%{span | content: text} | kept], room - used}
        end)

      Enum.reverse([Span.raw("…") | kept])
    end
  end
end

defmodule Elui.Widgets.TextArea.VisualLayout do
  @moduledoc false

  alias Elui.Text.Width

  defmodule Row do
    @moduledoc false
    defstruct graphemes: [], start: 0, content_start: 0, end: 0, hard_end?: false
  end

  def layout(text, cursor, width, wrap) when wrap in [true, :word] and width > 0 do
    rows = wrapped_rows(text, width)
    {line_index, row} = locate_cursor(rows, cursor)

    col = cursor_column(row, cursor)

    {Enum.map(rows, &Enum.join(&1.graphemes)), line_index, col}
  end

  def layout(text, cursor, _width, _wrap) do
    lines = String.split(text, "\n")
    {line_index, grapheme_col} = cursor_line_col(text, cursor)
    row = Enum.at(lines, line_index) || ""
    col = row |> String.graphemes() |> Enum.take(grapheme_col) |> Enum.join() |> Width.of()
    {lines, line_index, col}
  end

  def move_vertical(text, cursor, width, delta) when width > 0 and delta in [-1, 1] do
    rows = wrapped_rows(text, width)
    {line_index, row} = locate_cursor(rows, cursor)

    desired_col = cursor_column(row, cursor)

    case line_index + delta do
      target when target < 0 -> 0
      target when target >= length(rows) -> length(String.graphemes(text))
      target -> rows |> Enum.at(target) |> cursor_for_column(desired_col)
    end
  end

  def take_columns(text, width) do
    text
    |> String.graphemes()
    |> display_prefix(width)
    |> elem(0)
    |> Enum.join()
  end

  def cursor_symbol(row, col) do
    if col >= Width.of(row), do: " ", else: grapheme_at_column(row, col) || " "
  end

  def clamped_cursor(row, width) do
    case row |> String.graphemes() |> List.last() do
      nil ->
        {max(width - 1, 0), " "}

      grapheme ->
        grapheme_width = Width.grapheme_width(grapheme)
        {max(width - grapheme_width, 0), grapheme}
    end
  end

  defp wrapped_rows(text, width) do
    physical_lines = String.split(text, "\n", trim: false)

    {rows, _offset} =
      physical_lines
      |> Enum.with_index()
      |> Enum.reduce({[], 0}, fn {line, index}, {rows, offset} ->
        graphemes = String.graphemes(line)
        final_physical_line? = index == length(physical_lines) - 1
        line_rows = wrap_graphemes(graphemes, width, offset, final_physical_line?)
        hard_row_index = length(line_rows) - 1

        line_rows =
          line_rows
          |> Enum.with_index()
          |> Enum.map(fn {row, row_index} ->
            %{row | hard_end?: row_index == hard_row_index}
          end)

        newline = if index < length(physical_lines) - 1, do: 1, else: 0
        {rows ++ line_rows, offset + length(graphemes) + newline}
      end)

    rows
  end

  defp wrap_graphemes([], _width, offset, _append_cursor_row?) do
    [%Row{start: offset, content_start: offset, end: offset, hard_end?: true}]
  end

  defp wrap_graphemes(graphemes, width, offset, append_cursor_row?) do
    rows = do_wrap_graphemes(graphemes, width, offset, false, []) |> Enum.reverse()

    case List.last(rows) do
      %Row{graphemes: graphemes, end: ending} when graphemes != [] ->
        if append_cursor_row? and Width.of(Enum.join(graphemes)) == width do
          rows ++ [%Row{start: ending, content_start: ending, end: ending}]
        else
          rows
        end

      _row ->
        rows
    end
  end

  defp do_wrap_graphemes([], _width, _offset, _soft_start?, rows), do: rows

  defp do_wrap_graphemes(graphemes, width, offset, soft_start?, rows) do
    {hidden, visible} =
      if soft_start?, do: Enum.split_while(graphemes, &whitespace?/1), else: {[], graphemes}

    content_start = offset + length(hidden)
    {prefix, _used} = display_prefix(visible, width)
    fit = length(prefix)

    split_at =
      if fit >= length(visible) do
        length(visible)
      else
        prefix
        |> last_whitespace_boundary()
        |> case do
          nil -> max(fit, 1)
          boundary -> boundary
        end
      end

    {line, rest} = Enum.split(visible, split_at)
    ending = content_start + split_at

    row = %Row{
      graphemes: line,
      start: offset,
      content_start: content_start,
      end: ending
    }

    do_wrap_graphemes(rest, width, ending, true, [row | rows])
  end

  defp display_prefix(graphemes, width) do
    graphemes
    |> Enum.reduce_while({[], 0}, fn grapheme, {result, used} ->
      next = used + Width.grapheme_width(grapheme)

      if next <= max(width, 0) do
        {:cont, {[grapheme | result], next}}
      else
        {:halt, {result, used}}
      end
    end)
    |> then(fn {result, used} -> {Enum.reverse(result), used} end)
  end

  defp last_whitespace_boundary(graphemes) do
    graphemes
    |> Enum.with_index(1)
    |> Enum.reverse()
    |> Enum.find_value(fn {grapheme, boundary} ->
      if whitespace?(grapheme), do: boundary
    end)
  end

  defp whitespace?(grapheme), do: String.trim(grapheme) == ""

  defp locate_cursor(rows, cursor) do
    rows
    |> Enum.with_index()
    |> Enum.find_value({0, List.first(rows)}, fn {row, index} ->
      if cursor_on_row?(cursor, row), do: {index, row}
    end)
  end

  defp cursor_on_row?(cursor, row) do
    cursor >= row.start and
      (cursor < row.end or (cursor == row.end and row.hard_end?))
  end

  defp cursor_for_column(row, desired_col) do
    {prefix, _width} = display_prefix(row.graphemes, desired_col)
    row.content_start + length(prefix)
  end

  defp cursor_column(row, cursor) do
    row.graphemes
    |> Enum.take(max(cursor - row.content_start, 0))
    |> Enum.join()
    |> Width.of()
  end

  defp grapheme_at_column(text, target) do
    text
    |> String.graphemes()
    |> Enum.reduce_while({nil, 0}, fn grapheme, {_found, used} ->
      width = Width.grapheme_width(grapheme)

      if target < used + width do
        {:halt, {grapheme, used}}
      else
        {:cont, {nil, used + width}}
      end
    end)
    |> elem(0)
  end

  defp cursor_line_col(text, cursor) do
    graphemes = String.graphemes(text)
    {before, _} = Enum.split(graphemes, cursor)
    lines = before |> Enum.join() |> String.split("\n")
    {length(lines) - 1, lines |> List.last() |> then(&String.graphemes(&1 || "")) |> length()}
  end
end

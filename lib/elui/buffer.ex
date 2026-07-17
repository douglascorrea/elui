defmodule Elui.Buffer do
  @moduledoc """
  A grid of styled cells mapped to a rectangular area of the terminal.

  Widgets render into a buffer; the terminal then diffs consecutive
  buffers and only writes the cells that changed. Mirrors ratatui's
  `Buffer`.
  """

  alias Elui.Buffer.Cell
  alias Elui.Layout.Rect
  alias Elui.Style
  alias Elui.Text.{Line, Span, Width}

  defstruct area: %Rect{}, cells: %{}

  @type t :: %__MODULE__{area: Rect.t(), cells: %{{integer(), integer()} => Cell.t()}}

  @doc "Creates an empty buffer covering `area`."
  @spec empty(Rect.t()) :: t()
  def empty(%Rect{} = area), do: %__MODULE__{area: area, cells: %{}}

  @doc "Creates a buffer filled with the given cell."
  @spec filled(Rect.t(), Cell.t()) :: t()
  def filled(%Rect{} = area, %Cell{} = cell) do
    cells = for pos <- Rect.positions(area), into: %{}, do: {pos, cell}
    %__MODULE__{area: area, cells: cells}
  end

  @doc "Returns the cell at `{x, y}` (an empty cell when unset)."
  @spec get(t(), integer(), integer()) :: Cell.t()
  def get(%__MODULE__{cells: cells}, x, y) do
    Map.get(cells, {x, y}, Cell.empty())
  end

  @doc "Puts a cell at `{x, y}`, ignoring positions outside the buffer area."
  @spec put(t(), integer(), integer(), Cell.t()) :: t()
  def put(%__MODULE__{} = buffer, x, y, %Cell{} = cell) do
    if Rect.contains?(buffer.area, {x, y}) do
      %{buffer | cells: Map.put(buffer.cells, {x, y}, cell)}
    else
      buffer
    end
  end

  @doc "Sets the symbol at `{x, y}` keeping the existing style."
  @spec set_symbol(t(), integer(), integer(), String.t()) :: t()
  def set_symbol(%__MODULE__{} = buffer, x, y, symbol) do
    put(buffer, x, y, Cell.set_symbol(get(buffer, x, y), symbol))
  end

  @doc """
  Writes a string starting at `{x, y}`, clipped to the buffer area.
  Returns the updated buffer.
  """
  @spec set_string(t(), integer(), integer(), String.t(), Style.t() | Keyword.t() | nil) :: t()
  def set_string(%__MODULE__{} = buffer, x, y, string, style \\ nil) do
    {buffer, _next_x} =
      set_stringn(buffer, x, y, string, buffer.area.x + buffer.area.width - x, style)

    buffer
  end

  @doc """
  Writes at most `max_width` cells of a string starting at `{x, y}`.
  Returns `{buffer, next_x}`.
  """
  @spec set_stringn(
          t(),
          integer(),
          integer(),
          String.t(),
          integer(),
          Style.t() | Keyword.t() | nil
        ) ::
          {t(), integer()}
  def set_stringn(%__MODULE__{} = buffer, x, y, string, max_width, style \\ nil) do
    style = Style.to_style(style)
    max_x = min(x + max_width, buffer.area.x + buffer.area.width)

    string
    |> String.graphemes()
    |> Enum.reduce({buffer, x}, fn grapheme, {buf, cx} ->
      width = Width.grapheme_width(grapheme)

      cond do
        width == 0 ->
          {buf, cx}

        cx + width > max_x ->
          {buf, cx}

        true ->
          cell =
            buf
            |> get(cx, y)
            |> Cell.set_symbol(grapheme)
            |> Cell.set_style(style)
            |> Map.put(:skip, false)

          buf = put(buf, cx, y, cell)

          # Mark trailing cells of wide graphemes so the diff skips them.
          buf =
            if width > 1 do
              trailing =
                buf
                |> get(cx + 1, y)
                |> Cell.set_symbol("")
                |> Cell.set_style(style)
                |> Map.put(:skip, true)

              put(buf, cx + 1, y, trailing)
            else
              buf
            end

          {buf, cx + width}
      end
    end)
  end

  @doc "Writes a `Elui.Text.Span` at `{x, y}`. Returns `{buffer, next_x}`."
  @spec set_span(t(), integer(), integer(), Span.t(), integer()) :: {t(), integer()}
  def set_span(%__MODULE__{} = buffer, x, y, %Span{} = span, max_width) do
    set_stringn(buffer, x, y, span.content, max_width, span.style)
  end

  @doc """
  Writes a `Elui.Text.Line` at `{x, y}`, honoring the line's alignment
  within `max_width`. Returns `{buffer, next_x}`.
  """
  @spec set_line(t(), integer(), integer(), Line.t(), integer()) :: {t(), integer()}
  def set_line(%__MODULE__{} = buffer, x, y, %Line{} = line, max_width) do
    line_width = Line.width(line)

    x =
      case line.alignment do
        :center -> x + max(div(max_width - line_width, 2), 0)
        :right -> x + max(max_width - line_width, 0)
        _ -> x
      end

    max_x = min(x + max_width, buffer.area.x + buffer.area.width)

    Enum.reduce(line.spans, {buffer, x}, fn span, {buf, cx} ->
      span = %{span | style: Style.patch(line.style, span.style)}
      set_span(buf, cx, y, span, max_x - cx)
    end)
  end

  @doc "Patches the style of every cell inside `area`."
  @spec set_style(t(), Rect.t(), Style.t() | Keyword.t()) :: t()
  def set_style(%__MODULE__{} = buffer, %Rect{} = area, style) do
    style = Style.to_style(style)
    area = Rect.intersection(buffer.area, area)

    cells =
      Enum.reduce(Rect.positions(area), buffer.cells, fn pos, cells ->
        cell = Map.get(cells, pos, Cell.empty())
        Map.put(cells, pos, Cell.set_style(cell, style))
      end)

    %{buffer | cells: cells}
  end

  @doc "Fills `area` with the given cell."
  @spec fill(t(), Rect.t(), Cell.t()) :: t()
  def fill(%__MODULE__{} = buffer, %Rect{} = area, %Cell{} = cell) do
    area = Rect.intersection(buffer.area, area)

    cells =
      Enum.reduce(Rect.positions(area), buffer.cells, fn pos, cells ->
        Map.put(cells, pos, cell)
      end)

    %{buffer | cells: cells}
  end

  @doc "Clears symbols inside `area` while preserving each cell's inherited style."
  @spec clear(t(), Rect.t()) :: t()
  def clear(%__MODULE__{} = buffer, %Rect{} = area) do
    area = Rect.intersection(buffer.area, area)

    cells =
      Enum.reduce(Rect.positions(area), buffer.cells, fn pos, cells ->
        cell =
          cells
          |> Map.get(pos, Cell.empty())
          |> Cell.set_symbol(" ")
          |> Map.put(:skip, false)

        Map.put(cells, pos, cell)
      end)

    %{buffer | cells: cells}
  end

  @doc "Resets every cell to the empty state."
  @spec reset(t()) :: t()
  def reset(%__MODULE__{} = buffer), do: %{buffer | cells: %{}}

  @doc """
  Computes the difference between two buffers as a list of
  `{x, y, cell}` updates needed to turn `previous` into `next`.
  """
  @spec diff(t(), t()) :: [{integer(), integer(), Cell.t()}]
  def diff(%__MODULE__{} = previous, %__MODULE__{} = next) do
    next.area
    |> Rect.positions()
    |> Enum.flat_map(fn {x, y} ->
      prev_cell = get(previous, x, y)
      next_cell = get(next, x, y)

      if prev_cell == next_cell or next_cell.skip do
        []
      else
        [{x, y, next_cell}]
      end
    end)
  end

  @doc "Renders the buffer content as a list of plain strings (one per row), useful in tests."
  @spec to_lines(t()) :: [String.t()]
  def to_lines(%__MODULE__{} = buffer) do
    area = buffer.area

    for y <- area.y..(Rect.bottom(area) - 1)//1 do
      Enum.map_join(area.x..(Rect.right(area) - 1)//1, fn x ->
        cell = get(buffer, x, y)
        if cell.skip, do: "", else: cell.symbol
      end)
    end
  end
end

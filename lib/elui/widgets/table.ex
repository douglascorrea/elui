defmodule Elui.Widgets.Table.State do
  @moduledoc """
  Selection and scroll state for `Elui.Widgets.Table`.
  Mirrors ratatui's `TableState`.
  """

  defstruct offset: 0, selected: nil, selected_column: nil

  @type t :: %__MODULE__{
          offset: non_neg_integer(),
          selected: non_neg_integer() | nil,
          selected_column: non_neg_integer() | nil
        }

  @spec new(Keyword.t()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      offset: Keyword.get(opts, :offset, 0),
      selected: Keyword.get(opts, :selected),
      selected_column: Keyword.get(opts, :selected_column)
    }
  end

  @spec select(t(), non_neg_integer() | nil) :: t()
  def select(%__MODULE__{} = state, index), do: %{state | selected: index}

  @spec select_column(t(), non_neg_integer() | nil) :: t()
  def select_column(%__MODULE__{} = state, index), do: %{state | selected_column: index}

  @spec select_next(t(), non_neg_integer()) :: t()
  def select_next(%__MODULE__{} = state, count) when count > 0 do
    %{state | selected: rem((state.selected || -1) + 1, count)}
  end

  def select_next(state, _), do: state

  @spec select_previous(t(), non_neg_integer()) :: t()
  def select_previous(%__MODULE__{} = state, count) when count > 0 do
    %{state | selected: rem((state.selected || count) - 1 + count, count)}
  end

  def select_previous(state, _), do: state
end

defmodule Elui.Widgets.Table.Row do
  @moduledoc "A table row: a list of cells with an optional style and height."

  alias Elui.Style
  alias Elui.Text

  defstruct cells: [], style: %Style{}, height: 1, top_margin: 0, bottom_margin: 0

  @type t :: %__MODULE__{}

  @doc "Creates a row from cell contents (strings, lines or texts)."
  @spec new([term()], Keyword.t()) :: t()
  def new(cells, opts \\ []) do
    %__MODULE__{
      cells: Enum.map(cells, &Text.to_text/1),
      style: Style.to_style(Keyword.get(opts, :style)),
      height: Keyword.get(opts, :height, 1),
      top_margin: Keyword.get(opts, :top_margin, 0),
      bottom_margin: Keyword.get(opts, :bottom_margin, 0)
    }
  end

  @doc "Total vertical space taken by the row."
  @spec total_height(t()) :: non_neg_integer()
  def total_height(%__MODULE__{} = row), do: row.height + row.top_margin + row.bottom_margin
end

defmodule Elui.Widgets.Table do
  @moduledoc """
  A table with a header, footer, rows and per-column width constraints.
  Mirrors ratatui's `Table` / `TableState`.

  ## Example

      Table.new(
        [
          Row.new(["Cell1", "Cell2"]),
          Row.new(["Cell3", "Cell4"])
        ],
        [{:length, 10}, {:fill, 1}],
        header: Row.new(["Name", "Value"], style: [add_modifier: [:bold]]),
        block: Block.bordered(title: "Table"),
        row_highlight_style: [bg: :blue]
      )
  """

  alias Elui.Buffer
  alias Elui.Layout
  alias Elui.Layout.Rect
  alias Elui.Style
  alias Elui.Widgets.Block
  alias Elui.Widgets.Table.{Row, State}

  defstruct rows: [],
            widths: [],
            header: nil,
            footer: nil,
            block: nil,
            style: %Style{},
            column_spacing: 1,
            row_highlight_style: %Style{},
            column_highlight_style: %Style{},
            cell_highlight_style: %Style{},
            highlight_symbol: "",
            flex: :start

  @type t :: %__MODULE__{}

  @doc """
  Creates a table.

  `rows` is a list of `Elui.Widgets.Table.Row` (or lists of cell
  contents), `widths` a list of layout constraints, one per column.

  Options: `:header`, `:footer`, `:block`, `:style`, `:column_spacing`,
  `:row_highlight_style`, `:column_highlight_style`,
  `:cell_highlight_style`, `:highlight_symbol`, `:flex`.
  """
  @spec new([Row.t() | [term()]], [Elui.Layout.Constraint.t()], Keyword.t()) :: t()
  def new(rows, widths, opts \\ []) do
    rows =
      Enum.map(rows, fn
        %Row{} = row -> row
        cells when is_list(cells) -> Row.new(cells)
      end)

    %__MODULE__{
      rows: rows,
      widths: widths,
      header: Keyword.get(opts, :header),
      footer: Keyword.get(opts, :footer),
      block: Keyword.get(opts, :block),
      style: Style.to_style(Keyword.get(opts, :style)),
      column_spacing: Keyword.get(opts, :column_spacing, 1),
      row_highlight_style: Style.to_style(Keyword.get(opts, :row_highlight_style)),
      column_highlight_style: Style.to_style(Keyword.get(opts, :column_highlight_style)),
      cell_highlight_style: Style.to_style(Keyword.get(opts, :cell_highlight_style)),
      highlight_symbol: Keyword.get(opts, :highlight_symbol, ""),
      flex: Keyword.get(opts, :flex, :start)
    }
  end

  @doc false
  def render_into(%__MODULE__{} = table, area, buffer, %State{} = state) do
    buffer = Buffer.set_style(buffer, area, table.style)
    {inner, buffer} = Block.render_with_block(table.block, area, buffer)

    if Rect.empty?(inner) do
      {buffer, state}
    else
      symbol_width = Elui.Text.Width.of(table.highlight_symbol)
      columns_area = Rect.inner(inner, left: symbol_width, right: 0, top: 0, bottom: 0)
      columns = column_areas(table, columns_area)

      header_height = if table.header, do: Row.total_height(table.header), else: 0
      footer_height = if table.footer, do: Row.total_height(table.footer), else: 0
      body_height = max(inner.height - header_height - footer_height, 0)

      buffer =
        if table.header do
          render_row(buffer, table.header, columns, inner.y + table.header.top_margin, nil)
        else
          buffer
        end

      offset = adjust_offset(state, table.rows, body_height)
      state = %{state | offset: offset}

      body_top = inner.y + header_height

      {buffer, _} =
        table.rows
        |> Enum.with_index()
        |> Enum.drop(offset)
        |> Enum.reduce_while({buffer, 0}, fn {row, index}, {buf, used} ->
          row_height = Row.total_height(row)

          if used + row_height > body_height do
            {:halt, {buf, used}}
          else
            y = body_top + used + row.top_margin
            selected? = state.selected == index

            buf =
              if selected? do
                row_area = Rect.new(inner.x, y, inner.width, row.height)

                buf =
                  if table.highlight_symbol != "" do
                    Buffer.set_string(
                      buf,
                      inner.x,
                      y,
                      table.highlight_symbol,
                      table.row_highlight_style
                    )
                  else
                    buf
                  end

                Buffer.set_style(buf, row_area, table.row_highlight_style)
              else
                buf
              end

            buf = render_row(buf, row, columns, y, if(selected?, do: table.row_highlight_style))

            buf =
              maybe_highlight_column(buf, table, state, columns, body_top, body_height)

            buf = maybe_highlight_cell(buf, table, state, columns, index, y, row.height)

            {:cont, {buf, used + row_height}}
          end
        end)

      buffer =
        if table.footer do
          y = Rect.bottom(inner) - footer_height + table.footer.top_margin
          render_row(buffer, table.footer, columns, y, nil)
        else
          buffer
        end

      {buffer, state}
    end
  end

  defp maybe_highlight_column(buffer, _table, %State{selected_column: nil}, _cols, _top, _h),
    do: buffer

  defp maybe_highlight_column(buffer, table, %State{selected_column: col}, columns, top, height) do
    case Enum.at(columns, col) do
      nil ->
        buffer

      column ->
        Buffer.set_style(
          buffer,
          Rect.new(column.x, top, column.width, height),
          table.column_highlight_style
        )
    end
  end

  defp maybe_highlight_cell(buffer, table, state, columns, row_index, y, height) do
    with true <- state.selected == row_index,
         col when not is_nil(col) <- state.selected_column,
         %Rect{} = column <- Enum.at(columns, col) do
      Buffer.set_style(
        buffer,
        Rect.new(column.x, y, column.width, height),
        table.cell_highlight_style
      )
    else
      _ -> buffer
    end
  end

  defp adjust_offset(%State{selected: nil, offset: offset}, _rows, _height), do: offset

  defp adjust_offset(%State{selected: selected, offset: offset}, rows, height) do
    count = length(rows)
    selected = min(selected, max(count - 1, 0))
    heights = Enum.map(rows, &Row.total_height/1)

    cond do
      selected < offset ->
        selected

      true ->
        Enum.reduce_while(offset..selected, offset, fn candidate, _acc ->
          used = heights |> Enum.slice(candidate..selected) |> Enum.sum()
          if used <= height, do: {:halt, candidate}, else: {:cont, candidate + 1}
        end)
    end
  end

  defp column_areas(table, area) do
    Layout.horizontal(table.widths, spacing: table.column_spacing, flex: table.flex)
    |> Layout.split(area)
  end

  defp render_row(buffer, %Row{} = row, columns, y, extra_style) do
    row.cells
    |> Enum.zip(columns)
    |> Enum.reduce(buffer, fn {cell, column}, buf ->
      cell.lines
      |> Enum.take(row.height)
      |> Enum.with_index()
      |> Enum.reduce(buf, fn {line, i}, b ->
        line =
          line
          |> Elui.Text.Line.patch_style(cell.style)
          |> Elui.Text.Line.patch_style(row.style)
          |> then(fn l ->
            if extra_style, do: Elui.Text.Line.patch_style(l, extra_style), else: l
          end)

        line = %{line | alignment: line.alignment || cell.alignment}
        {b, _} = Buffer.set_line(b, column.x, y + i, line, column.width)
        b
      end)
    end)
  end

  defimpl Elui.Widget do
    def render(table, area, buffer) do
      {buffer, _} = Elui.Widgets.Table.render_into(table, area, buffer, %State{})
      buffer
    end
  end

  defimpl Elui.StatefulWidget do
    def render(table, area, buffer, state) do
      Elui.Widgets.Table.render_into(table, area, buffer, state)
    end
  end
end

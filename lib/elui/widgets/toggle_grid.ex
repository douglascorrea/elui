defmodule Elui.Widgets.ToggleGrid.State do
  @moduledoc """
  Focus state for `Elui.Widgets.ToggleGrid`.

  `focus` is one of:

    * `{:cell, row, col}` — a toggle cell
    * `{:row_action, row}` — the per-row action (e.g. delete)
    * `:add` — the trailing add-row control
  """

  defstruct focus: :add, offset: 0

  @type focus ::
          {:cell, non_neg_integer(), non_neg_integer()} | {:row_action, non_neg_integer()} | :add
  @type t :: %__MODULE__{focus: focus(), offset: non_neg_integer()}

  @doc "Creates toggle-grid focus and scroll state."
  @spec new(Keyword.t()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      focus: Keyword.get(opts, :focus, :add),
      offset: Keyword.get(opts, :offset, 0)
    }
  end

  @doc "Moves focus by `{drow, dcol}` within a grid of `row_count` rows and `col_count` columns."
  @spec move(t(), {integer(), integer()}, non_neg_integer(), non_neg_integer(), keyword()) :: t()
  def move(%__MODULE__{} = state, {drow, dcol}, row_count, col_count, opts \\ []) do
    bounds = %{
      rows: row_count,
      columns: col_count,
      row_actions?: Keyword.get(opts, :row_actions, true),
      add_row?: Keyword.get(opts, :add_row, true)
    }

    case state.focus do
      {:cell, row, col} ->
        move_from_cell(state, row, col, drow, dcol, bounds)

      {:row_action, row} ->
        move_from_row_action(state, row, drow, dcol, bounds)

      :add ->
        move_from_add(state, drow, dcol, bounds)
    end
  end

  defp move_from_cell(state, row, col, drow, dcol, bounds) do
    cond do
      dcol < 0 and col == 0 and bounds.row_actions? ->
        %{state | focus: {:row_action, row}}

      dcol < 0 and col > 0 ->
        %{state | focus: {:cell, row, col - 1}}

      dcol > 0 and col + 1 < bounds.columns ->
        %{state | focus: {:cell, row, col + 1}}

      drow < 0 and row > 0 ->
        %{state | focus: {:cell, row - 1, col}}

      drow > 0 and row + 1 < bounds.rows ->
        %{state | focus: {:cell, row + 1, col}}

      drow > 0 and row + 1 >= bounds.rows and bounds.add_row? ->
        %{state | focus: :add}

      true ->
        state
    end
  end

  defp move_from_row_action(state, row, drow, dcol, bounds) do
    cond do
      dcol > 0 and bounds.columns > 0 ->
        %{state | focus: {:cell, row, 0}}

      drow < 0 and row > 0 ->
        %{state | focus: {:row_action, row - 1}}

      drow > 0 and row + 1 < bounds.rows ->
        %{state | focus: {:row_action, row + 1}}

      drow > 0 and row + 1 >= bounds.rows and bounds.add_row? ->
        %{state | focus: :add}

      true ->
        state
    end
  end

  defp move_from_add(state, drow, _dcol, bounds) do
    cond do
      drow < 0 and bounds.rows > 0 and bounds.row_actions? ->
        %{state | focus: {:row_action, bounds.rows - 1}}

      drow < 0 and bounds.rows > 0 and bounds.columns > 0 ->
        %{state | focus: {:cell, bounds.rows - 1, 0}}

      true ->
        state
    end
  end
end

defmodule Elui.Widgets.ToggleGrid do
  @moduledoc """
  A day×time style toggle matrix with optional per-row actions and an
  add-row control. Apps own mutation; this widget renders checked state
  and focus.
  """

  alias Elui.Buffer
  alias Elui.Layout.Rect
  alias Elui.Style
  alias Elui.Widgets.Block
  alias Elui.Widgets.ToggleGrid.State

  defstruct columns: [],
            rows: [],
            block: nil,
            style: %Style{},
            header_style: %Style{},
            checked_style: %Style{},
            unchecked_style: %Style{},
            focus_style: %Style{},
            cell_width: 4,
            checked_symbol: "[x]",
            unchecked_symbol: "[ ]",
            row_action: "x",
            add_label: "+ Add",
            show_row_actions: true,
            show_add_row: true

  @type row :: %{label: String.t(), cells: [boolean()]}
  @type t :: %__MODULE__{}

  @doc """
  Creates a toggle grid.

  `columns` are header labels. `rows` is a list of maps with `:label`
  and `:cells` (booleans, one per column).

  Options: `:block`, `:style`, `:header_style`, `:checked_style`,
  `:unchecked_style`, `:focus_style`, `:cell_width`, `:checked_symbol`,
  `:unchecked_symbol`, `:row_action`, `:add_label`, `:show_row_actions`,
  `:show_add_row`.
  """
  @spec new([String.t()], [row()], Keyword.t()) :: t()
  def new(columns, rows, opts \\ []) when is_list(columns) and is_list(rows) do
    checked_symbol = Keyword.get(opts, :checked_symbol, "[x]")
    unchecked_symbol = Keyword.get(opts, :unchecked_symbol, "[ ]")

    cell_width =
      opts
      |> Keyword.get(:cell_width, 4)
      |> max(String.length(checked_symbol) + 1)
      |> max(String.length(unchecked_symbol) + 1)

    %__MODULE__{
      columns: columns,
      rows: rows,
      block: Keyword.get(opts, :block),
      style: Style.to_style(Keyword.get(opts, :style)),
      header_style: Style.to_style(Keyword.get(opts, :header_style)),
      checked_style: Style.to_style(Keyword.get(opts, :checked_style, fg: :cyan)),
      unchecked_style: Style.to_style(Keyword.get(opts, :unchecked_style, fg: :dark_gray)),
      focus_style: Style.to_style(Keyword.get(opts, :focus_style, bg: :blue, fg: :white)),
      cell_width: cell_width,
      checked_symbol: checked_symbol,
      unchecked_symbol: unchecked_symbol,
      row_action: Keyword.get(opts, :row_action, "x"),
      add_label: Keyword.get(opts, :add_label, "+ Add"),
      show_row_actions: Keyword.get(opts, :show_row_actions, true),
      show_add_row: Keyword.get(opts, :show_add_row, true)
    }
  end

  @doc false
  def render_into(%__MODULE__{} = grid, area, buffer, %State{} = state) do
    buffer = Buffer.set_style(buffer, area, grid.style)
    {inner, buffer} = Block.render_with_block(grid.block, area, buffer)

    if Rect.empty?(inner) do
      {buffer, state}
    else
      col_count = length(grid.columns)
      label_width = label_width(grid)
      action_width = if grid.show_row_actions, do: 2, else: 0
      cell_width = grid.cell_width

      buffer = render_header(buffer, grid, inner, label_width, action_width, cell_width)

      {buffer, state} =
        render_rows(buffer, grid, state, inner, label_width, action_width, cell_width, col_count)

      buffer =
        if grid.show_add_row do
          render_add(buffer, grid, state, inner, label_width)
        else
          buffer
        end

      {buffer, state}
    end
  end

  defp label_width(grid) do
    labels = Enum.map(grid.rows, & &1.label)
    labels = if grid.show_add_row, do: [grid.add_label | labels], else: labels
    max(4, Enum.reduce(labels, 4, fn label, acc -> max(acc, String.length(label)) end))
  end

  defp render_header(buffer, grid, inner, label_width, action_width, cell_width) do
    x = inner.x
    y = inner.y

    buffer =
      Buffer.set_string(buffer, x, y, String.pad_trailing("Time", label_width), grid.header_style)

    x = x + label_width + 1

    buffer =
      if grid.show_row_actions do
        Buffer.set_string(buffer, x, y, String.pad_trailing("", action_width), grid.header_style)
      else
        buffer
      end

    x = if grid.show_row_actions, do: x + action_width, else: x

    Enum.reduce(Enum.with_index(grid.columns), buffer, fn {column, index}, buf ->
      Buffer.set_string(
        buf,
        x + index * cell_width,
        y,
        String.pad_trailing(String.slice(column, 0, 3), cell_width),
        grid.header_style
      )
    end)
  end

  defp render_rows(buffer, grid, state, inner, label_width, action_width, cell_width, col_count) do
    visible_height = max(inner.height - 1 - if(grid.show_add_row, do: 1, else: 0), 0)
    offset = clamp_offset(state, length(grid.rows), visible_height)
    state = %{state | offset: offset}

    buffer =
      grid.rows
      |> Enum.with_index()
      |> Enum.drop(offset)
      |> Enum.take(visible_height)
      |> Enum.reduce(buffer, fn {row, row_index}, buf ->
        y = inner.y + 1 + (row_index - offset)

        render_row(
          buf,
          grid,
          state,
          row,
          row_index,
          inner.x,
          y,
          label_width,
          action_width,
          cell_width,
          col_count
        )
      end)

    {buffer, state}
  end

  defp render_row(
         buffer,
         grid,
         state,
         row,
         row_index,
         x,
         y,
         label_width,
         action_width,
         cell_width,
         col_count
       ) do
    buffer =
      Buffer.set_string(buffer, x, y, String.pad_trailing(row.label, label_width), grid.style)

    x = x + label_width + 1

    buffer =
      if grid.show_row_actions do
        focused? = state.focus == {:row_action, row_index}
        style = if focused?, do: grid.focus_style, else: grid.style
        Buffer.set_string(buffer, x, y, String.pad_trailing(grid.row_action, action_width), style)
      else
        buffer
      end

    x = if grid.show_row_actions, do: x + action_width, else: x

    Enum.reduce(0..(col_count - 1)//1, buffer, fn col, buf ->
      checked? = Enum.at(row.cells, col, false)
      symbol = if checked?, do: grid.checked_symbol, else: grid.unchecked_symbol
      focused? = state.focus == {:cell, row_index, col}

      style =
        cond do
          focused? -> grid.focus_style
          checked? -> grid.checked_style
          true -> grid.unchecked_style
        end

      cell_x = x + col * cell_width
      Buffer.set_string(buf, cell_x, y, symbol, style)
    end)
  end

  defp render_add(buffer, grid, state, inner, label_width) do
    y = Rect.bottom(inner) - 1
    focused? = state.focus == :add
    style = if focused?, do: grid.focus_style, else: grid.style

    Buffer.set_string(
      buffer,
      inner.x,
      y,
      String.pad_trailing(grid.add_label, label_width + 8),
      style
    )
  end

  defp clamp_offset(state, row_count, visible_height) do
    focus_row =
      case state.focus do
        {:cell, row, _} -> row
        {:row_action, row} -> row
        :add -> max(row_count - 1, 0)
      end

    offset = state.offset
    offset = if focus_row < offset, do: focus_row, else: offset

    offset =
      if focus_row >= offset + visible_height, do: focus_row - visible_height + 1, else: offset

    max(min(offset, max(row_count - visible_height, 0)), 0)
  end

  defimpl Elui.Widget do
    def render(grid, area, buffer) do
      {buffer, _state} =
        Elui.Widgets.ToggleGrid.render_into(grid, area, buffer, %Elui.Widgets.ToggleGrid.State{})

      buffer
    end
  end

  defimpl Elui.StatefulWidget do
    def render(grid, area, buffer, state) do
      Elui.Widgets.ToggleGrid.render_into(grid, area, buffer, state)
    end
  end
end

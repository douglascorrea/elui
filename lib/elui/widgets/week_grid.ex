defmodule Elui.Widgets.WeekGrid.State do
  @moduledoc """
  Focus state for `Elui.Widgets.WeekGrid`.

  `selected_day` is a column index `0..6`. `selected_item` is an optional
  line index within that day (including overflow-aware visible lines).
  """

  defstruct selected_day: 0, selected_item: 0, scroll: 0

  @type t :: %__MODULE__{
          selected_day: non_neg_integer(),
          selected_item: non_neg_integer(),
          scroll: non_neg_integer()
        }

  @spec new(Keyword.t()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      selected_day: Keyword.get(opts, :selected_day, 0),
      selected_item: Keyword.get(opts, :selected_item, 0),
      scroll: Keyword.get(opts, :scroll, 0)
    }
  end

  @doc "Moves focus by `{dday, ditem}` across `day_count` columns."
  @spec move(t(), {integer(), integer()}, non_neg_integer(), (non_neg_integer() ->
                                                                non_neg_integer())) ::
          t()
  def move(%__MODULE__{} = state, {dday, ditem}, day_count, item_count_fun)
      when day_count > 0 and is_function(item_count_fun, 1) do
    day = Integer.mod(state.selected_day + dday, day_count)
    count = item_count_fun.(day)

    item =
      cond do
        count <= 0 -> 0
        dday != 0 -> min(state.selected_item, count - 1)
        true -> Integer.mod(state.selected_item + ditem, count)
      end

    %{state | selected_day: day, selected_item: item}
  end

  def move(state, _delta, _day_count, _item_count_fun), do: state
end

defmodule Elui.Widgets.WeekGrid do
  @moduledoc """
  A seven-column week calendar with multi-line day cells.

  Apps supply day columns (title + items). Each item is a map with
  `:text` and optional `:kind` (`:post` or `:marker`). The widget owns
  layout, truncation (`+N more`), and focus highlighting.
  """

  alias Elui.Buffer
  alias Elui.Layout.Rect
  alias Elui.Style
  alias Elui.Widgets.Block
  alias Elui.Widgets.WeekGrid.State

  defstruct days: [],
            block: nil,
            style: %Style{},
            header_style: %Style{},
            post_style: %Style{},
            marker_style: %Style{},
            focus_style: %Style{},
            selected_day_style: %Style{},
            min_column_width: 10

  @type item :: %{required(:text) => String.t(), optional(:kind) => :post | :marker}
  @type day :: %{
          required(:title) => String.t(),
          required(:items) => [item()],
          optional(:date) => Date.t()
        }
  @type t :: %__MODULE__{}

  @doc """
  Creates a week grid from up to seven day maps.

  Options: `:block`, `:style`, `:header_style`, `:post_style`,
  `:marker_style`, `:focus_style`, `:selected_day_style`, and
  `:min_column_width`. Apps can use `fits?/2` to choose a narrow fallback.
  """
  @spec new([day()], Keyword.t()) :: t()
  def new(days, opts \\ []) when is_list(days) do
    %__MODULE__{
      days: Enum.take(days, 7),
      block: Keyword.get(opts, :block),
      style: Style.to_style(Keyword.get(opts, :style)),
      header_style: Style.to_style(Keyword.get(opts, :header_style, fg: :dark_gray)),
      post_style: Style.to_style(Keyword.get(opts, :post_style)),
      marker_style: Style.to_style(Keyword.get(opts, :marker_style, fg: :dark_gray)),
      focus_style: Style.to_style(Keyword.get(opts, :focus_style, bg: :blue, fg: :white)),
      selected_day_style:
        Style.to_style(Keyword.get(opts, :selected_day_style, add_modifier: [:bold])),
      min_column_width: max(Keyword.get(opts, :min_column_width, 10), 1)
    }
  end

  @doc "Returns whether every day column meets the widget's configured minimum width."
  @spec fits?(t(), Rect.t()) :: boolean()
  def fits?(%__MODULE__{} = grid, %Rect{} = area) do
    inner = if grid.block, do: Block.inner(grid.block, area), else: area
    day_count = length(grid.days)

    day_count == 0 or div(inner.width, day_count) >= grid.min_column_width
  end

  @doc false
  def render_into(%__MODULE__{} = grid, area, buffer, %State{} = state) do
    buffer = Buffer.set_style(buffer, area, grid.style)
    {inner, buffer} = Block.render_with_block(grid.block, area, buffer)

    if Rect.empty?(inner) or grid.days == [] do
      {buffer, state}
    else
      day_count = length(grid.days)
      col_width = max(div(inner.width, day_count), 1)
      body_height = max(inner.height - 1, 0)

      state = clamp_state(state, grid, body_height)

      buffer =
        grid.days
        |> Enum.with_index()
        |> Enum.reduce(buffer, fn {day, index}, buf ->
          x = inner.x + index * col_width
          width = column_width(inner, day_count, col_width, index)
          render_day(buf, grid, state, day, index, x, inner.y, width, body_height)
        end)

      {buffer, state}
    end
  end

  defp column_width(inner, day_count, col_width, index) do
    if index == day_count - 1 do
      max(inner.width - col_width * (day_count - 1), 1)
    else
      col_width
    end
  end

  defp clamp_state(state, grid, body_height) do
    day_count = length(grid.days)
    day = min(max(state.selected_day, 0), max(day_count - 1, 0))
    items = Enum.at(grid.days, day).items
    item_count = length(items)
    item = if item_count == 0, do: 0, else: min(max(state.selected_item, 0), item_count - 1)

    scroll =
      cond do
        body_height <= 0 -> 0
        item_count <= body_height -> 0
        item < state.scroll -> item
        item >= state.scroll + body_height -> item - body_height + 1
        true -> min(state.scroll, max(item_count - body_height, 0))
      end

    %{state | selected_day: day, selected_item: item, scroll: max(scroll, 0)}
  end

  defp render_day(buffer, grid, state, day, index, x, y, width, body_height) do
    selected_day? = state.selected_day == index

    header_style =
      if selected_day?,
        do: Style.patch(grid.header_style, grid.selected_day_style),
        else: grid.header_style

    title = String.slice(day.title || "", 0, max(width, 0))
    buffer = Buffer.set_string(buffer, x, y, String.pad_trailing(title, width), header_style)

    items = day.items || []
    scroll = if selected_day?, do: state.scroll, else: 0
    remaining = max(length(items) - scroll, 0)

    visible =
      if remaining > body_height and body_height > 0 do
        keep = body_height - 1

        items
        |> Enum.drop(scroll)
        |> Enum.take(keep)
        |> Kernel.++([%{text: "+#{remaining - keep} more", kind: :marker}])
      else
        items |> Enum.drop(scroll) |> Enum.take(body_height)
      end

    visible
    |> Enum.with_index()
    |> Enum.reduce(buffer, fn {item, item_offset}, buf ->
      item_index = scroll + item_offset
      focused? = selected_day? and state.selected_item == item_index
      style = item_style(grid, item, focused?)
      text = String.slice(item.text || "", 0, max(width, 0))
      Buffer.set_string(buf, x, y + 1 + item_offset, String.pad_trailing(text, width), style)
    end)
  end

  defp item_style(grid, _item, true), do: grid.focus_style

  defp item_style(grid, item, false) do
    case Map.get(item, :kind, :post) do
      :marker -> grid.marker_style
      _ -> grid.post_style
    end
  end

  defimpl Elui.Widget do
    def render(grid, area, buffer) do
      {buffer, _state} =
        Elui.Widgets.WeekGrid.render_into(grid, area, buffer, %Elui.Widgets.WeekGrid.State{})

      buffer
    end
  end

  defimpl Elui.StatefulWidget do
    def render(grid, area, buffer, state) do
      Elui.Widgets.WeekGrid.render_into(grid, area, buffer, state)
    end
  end
end

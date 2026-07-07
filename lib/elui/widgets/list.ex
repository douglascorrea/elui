defmodule Elui.Widgets.List.State do
  @moduledoc """
  Selection and scroll state for `Elui.Widgets.List`.
  Mirrors ratatui's `ListState`.
  """

  defstruct offset: 0, selected: nil

  @type t :: %__MODULE__{offset: non_neg_integer(), selected: non_neg_integer() | nil}

  @spec new(Keyword.t()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      offset: Keyword.get(opts, :offset, 0),
      selected: Keyword.get(opts, :selected)
    }
  end

  @doc "Selects the given index (or `nil` to clear the selection)."
  @spec select(t(), non_neg_integer() | nil) :: t()
  def select(%__MODULE__{} = state, index), do: %{state | selected: index}

  @doc "Moves the selection to the next item (wrapping at `count`)."
  @spec select_next(t(), non_neg_integer()) :: t()
  def select_next(%__MODULE__{} = state, count) when count > 0 do
    selected =
      case state.selected do
        nil -> 0
        i -> rem(i + 1, count)
      end

    %{state | selected: selected}
  end

  def select_next(state, _count), do: state

  @doc "Moves the selection to the previous item (wrapping at `count`)."
  @spec select_previous(t(), non_neg_integer()) :: t()
  def select_previous(%__MODULE__{} = state, count) when count > 0 do
    selected =
      case state.selected do
        nil -> count - 1
        i -> rem(i - 1 + count, count)
      end

    %{state | selected: selected}
  end

  def select_previous(state, _count), do: state

  @doc "Selects the first item."
  @spec select_first(t()) :: t()
  def select_first(%__MODULE__{} = state), do: %{state | selected: 0}

  @doc "Selects the last item."
  @spec select_last(t(), non_neg_integer()) :: t()
  def select_last(%__MODULE__{} = state, count), do: %{state | selected: max(count - 1, 0)}
end

defmodule Elui.Widgets.List do
  @moduledoc """
  A scrollable list of items with optional selection highlighting.
  Mirrors ratatui's `List` / `ListState`.

  Render it with `Elui.StatefulWidget.render/4` passing a
  `Elui.Widgets.List.State`, or with `Elui.Widget.render/3` for a
  stateless list.

  ## Example

      list =
        List.new(["Item 1", "Item 2", "Item 3"],
          block: Block.bordered(title: "Items"),
          highlight_style: [add_modifier: [:bold], bg: :blue],
          highlight_symbol: "> "
        )

      {buffer, state} = Elui.StatefulWidget.render(list, area, buffer, state)
  """

  alias Elui.Buffer
  alias Elui.Layout.Rect
  alias Elui.Style
  alias Elui.Text
  alias Elui.Widgets.Block
  alias Elui.Widgets.List.State

  defstruct items: [],
            block: nil,
            style: %Style{},
            highlight_style: %Style{},
            highlight_symbol: "",
            repeat_highlight_symbol: false,
            direction: :top_to_bottom,
            scroll_padding: 0

  @type t :: %__MODULE__{}

  @doc """
  Creates a list from items (strings, lines or texts).

  Options: `:block`, `:style`, `:highlight_style`, `:highlight_symbol`,
  `:repeat_highlight_symbol`, `:direction` (`:top_to_bottom` or
  `:bottom_to_top`), `:scroll_padding`.
  """
  @spec new([term()], Keyword.t()) :: t()
  def new(items, opts \\ []) do
    %__MODULE__{
      items: Enum.map(items, &Text.to_text/1),
      block: Keyword.get(opts, :block),
      style: Style.to_style(Keyword.get(opts, :style)),
      highlight_style: Style.to_style(Keyword.get(opts, :highlight_style)),
      highlight_symbol: Keyword.get(opts, :highlight_symbol, ""),
      repeat_highlight_symbol: Keyword.get(opts, :repeat_highlight_symbol, false),
      direction: Keyword.get(opts, :direction, :top_to_bottom),
      scroll_padding: Keyword.get(opts, :scroll_padding, 0)
    }
  end

  @doc "Number of items in the list."
  @spec len(t()) :: non_neg_integer()
  def len(%__MODULE__{items: items}), do: length(items)

  @doc false
  def render_into(%__MODULE__{} = list, area, buffer, %State{} = state) do
    buffer = Buffer.set_style(buffer, area, list.style)
    {inner, buffer} = Block.render_with_block(list.block, area, buffer)

    if Rect.empty?(inner) or list.items == [] do
      {buffer, state}
    else
      heights = Enum.map(list.items, &Text.height/1)
      offset = adjust_offset(state, heights, inner.height, list.scroll_padding)
      state = %{state | offset: offset}

      visible = visible_items(list, heights, offset, inner.height)

      buffer =
        Enum.reduce(visible, buffer, fn {item, index, y_offset, height}, buf ->
          y =
            case list.direction do
              :top_to_bottom -> inner.y + y_offset
              :bottom_to_top -> Rect.bottom(inner) - y_offset - height
            end

          selected? = state.selected == index
          render_item(buf, list, item, index, inner, y, height, selected?)
        end)

      {buffer, state}
    end
  end

  defp visible_items(list, heights, offset, max_height) do
    list.items
    |> Enum.with_index()
    |> Enum.drop(offset)
    |> Enum.reduce_while({[], 0}, fn {item, index}, {acc, used} ->
      height = Enum.at(heights, index, 1)

      if used >= max_height do
        {:halt, {acc, used}}
      else
        {:cont, {[{item, index, used, height} | acc], used + height}}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp adjust_offset(%State{selected: nil, offset: offset}, _heights, _height, _pad), do: offset

  defp adjust_offset(%State{selected: selected, offset: offset}, heights, height, _pad) do
    count = length(heights)
    selected = min(selected, count - 1)

    cond do
      selected < offset ->
        selected

      true ->
        # Increase offset until the selected item fits in the viewport.
        Enum.reduce_while(offset..selected, offset, fn candidate, _acc ->
          used =
            heights
            |> Enum.slice(candidate..selected)
            |> Enum.sum()

          if used <= height do
            {:halt, candidate}
          else
            {:cont, candidate + 1}
          end
        end)
    end
  end

  defp render_item(buffer, list, item, _index, inner, y, height, selected?) do
    symbol = if selected?, do: list.highlight_symbol, else: ""
    symbol_width = Elui.Text.Width.of(list.highlight_symbol)

    row_area = Rect.new(inner.x, y, inner.width, height)

    buffer =
      if selected? do
        Buffer.set_style(buffer, row_area, list.highlight_style)
      else
        buffer
      end

    item.lines
    |> Enum.with_index()
    |> Enum.reduce(buffer, fn {line, i}, buf ->
      row_y = y + i

      if row_y >= inner.y and row_y < Rect.bottom(inner) do
        prefix =
          cond do
            selected? and (i == 0 or list.repeat_highlight_symbol) -> symbol
            true -> String.duplicate(" ", symbol_width)
          end

        buf =
          if prefix != "" do
            style = if selected?, do: list.highlight_style, else: list.style
            Buffer.set_string(buf, inner.x, row_y, prefix, style)
          else
            buf
          end

        x = inner.x + symbol_width
        line = Elui.Text.Line.patch_style(line, item.style)

        line =
          if selected? do
            Elui.Text.Line.patch_style(line, list.highlight_style)
          else
            line
          end

        {buf, _} = Buffer.set_line(buf, x, row_y, line, inner.width - (x - inner.x))
        buf
      else
        buf
      end
    end)
  end

  defimpl Elui.Widget do
    def render(list, area, buffer) do
      {buffer, _state} = Elui.Widgets.List.render_into(list, area, buffer, %State{})
      buffer
    end
  end

  defimpl Elui.StatefulWidget do
    def render(list, area, buffer, state) do
      Elui.Widgets.List.render_into(list, area, buffer, state)
    end
  end
end

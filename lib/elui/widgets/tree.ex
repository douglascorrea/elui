defmodule Elui.Widgets.Tree.Item do
  @moduledoc """
  One node of an `Elui.Widgets.Tree`: an `id` unique in the whole tree, a
  `label` (anything `Elui.Text.to_text/1` takes: a string, a span, a line,
  a text), an optional `style` for the label, and `children`.
  """

  alias Elui.Style
  alias Elui.Text

  defstruct id: nil, label: %Text{}, style: %Style{}, children: []

  @type t :: %__MODULE__{id: term(), label: Text.t(), style: Style.t(), children: [t()]}

  @doc "Creates an item. Options: `:style`."
  @spec new(term(), term(), [t()], Keyword.t()) :: t()
  def new(id, label, children \\ [], opts \\ []) do
    %__MODULE__{
      id: id,
      label: Text.to_text(label),
      style: Style.to_style(Keyword.get(opts, :style)),
      children: children
    }
  end
end

defmodule Elui.Widgets.Tree.State do
  @moduledoc """
  Selection, folding and scroll state for `Elui.Widgets.Tree`.

  The selection is an item's id, not a row number, so it survives the
  tree being rebuilt: when the selected item disappears, the row that took
  its place is selected; when it is folded out of sight, its nearest
  visible ancestor is. Items are expanded unless their id is in
  `collapsed`. `nil` selects nothing; moving from there selects the first
  row.

  The functions that move take the tree's items, because only they say
  what the rows are. Moving stops at the first and last rows.
  """

  alias Elui.Widgets.Tree.Item

  defstruct selected: nil, collapsed: MapSet.new(), offset: 0, index: 0

  @type t :: %__MODULE__{
          selected: term() | nil,
          collapsed: MapSet.t(),
          offset: non_neg_integer(),
          index: non_neg_integer()
        }

  @doc """
  Creates tree state. Options: `:selected` (an id), `:collapsed` (ids
  whose children are hidden), `:offset` (the first visible row).
  """
  @spec new(Keyword.t()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      selected: Keyword.get(opts, :selected),
      collapsed: MapSet.new(Keyword.get(opts, :collapsed, [])),
      offset: Keyword.get(opts, :offset, 0)
    }
  end

  @doc "The visible rows, in order: `[{item, depth}]`, depth 0 at the top level."
  @spec rows([Item.t()], t()) :: [{Item.t(), non_neg_integer()}]
  def rows(items, %__MODULE__{} = state), do: rows(items, state, 0)

  defp rows(items, state, depth) do
    Enum.flat_map(items, fn item ->
      below =
        if item.children == [] or collapsed?(state, item.id),
          do: [],
          else: rows(item.children, state, depth + 1)

      [{item, depth} | below]
    end)
  end

  @doc "Whether the item with `id` has its children hidden."
  @spec collapsed?(t(), term()) :: boolean()
  def collapsed?(%__MODULE__{collapsed: collapsed}, id), do: MapSet.member?(collapsed, id)

  @doc "The selected item, wherever it is in the tree, or `nil`."
  @spec selected_item(t(), [Item.t()]) :: Item.t() | nil
  def selected_item(%__MODULE__{selected: nil}, _items), do: nil
  def selected_item(%__MODULE__{selected: id}, items), do: find(items, id)

  @doc "Selects the item with `id` (or nothing, with `nil`)."
  @spec select(t(), term() | nil) :: t()
  def select(%__MODULE__{} = state, id), do: %{state | selected: id}

  @doc """
  Makes the selection fit `items`: the selected row's index is recorded;
  an item that is gone gives way to the row now at its index, one folded
  out of sight to its nearest visible ancestor. Rendering does this.
  """
  @spec sync(t(), [Item.t()]) :: t()
  def sync(%__MODULE__{selected: nil} = state, _items), do: state

  def sync(%__MODULE__{selected: id} = state, items) do
    rows = rows(items, state)

    case Enum.find_index(rows, fn {item, _} -> item.id == id end) do
      nil when rows == [] ->
        %{state | selected: nil, index: 0}

      nil ->
        case visible_ancestor(items, id, rows) do
          nil ->
            index = min(state.index, length(rows) - 1)
            %{state | selected: row_id(rows, index), index: index}

          ancestor ->
            %{
              state
              | selected: ancestor,
                index: Enum.find_index(rows, &(elem(&1, 0).id == ancestor))
            }
        end

      index ->
        %{state | index: index}
    end
  end

  @doc "Selects the next row (the first when nothing is selected)."
  @spec select_next(t(), [Item.t()]) :: t()
  def select_next(state, items), do: select_by(state, items, 1)

  @doc "Selects the previous row (the first when nothing is selected)."
  @spec select_previous(t(), [Item.t()]) :: t()
  def select_previous(state, items), do: select_by(state, items, -1)

  @doc """
  Moves the selection `delta` rows down (negative: up), stopping at the
  first and last rows: for paging, pass the page's height.
  """
  @spec select_by(t(), [Item.t()], integer()) :: t()
  def select_by(%__MODULE__{} = state, items, delta) do
    state = sync(state, items)
    rows = rows(items, state)

    cond do
      rows == [] -> state
      state.selected == nil -> select_index(state, rows, 0)
      true -> select_index(state, rows, state.index + delta)
    end
  end

  @doc "Selects the first row."
  @spec select_first(t(), [Item.t()]) :: t()
  def select_first(%__MODULE__{} = state, items), do: select_index(state, rows(items, state), 0)

  @doc "Selects the last row."
  @spec select_last(t(), [Item.t()]) :: t()
  def select_last(%__MODULE__{} = state, items) do
    rows = rows(items, state)
    select_index(state, rows, length(rows) - 1)
  end

  @doc "Hides or shows the children of the item with `id`."
  @spec toggle(t(), term()) :: t()
  def toggle(%__MODULE__{} = state, id) do
    if collapsed?(state, id), do: expand(state, id), else: collapse(state, id)
  end

  @doc "Hides the children of the item with `id`."
  @spec collapse(t(), term()) :: t()
  def collapse(%__MODULE__{} = state, id),
    do: %{state | collapsed: MapSet.put(state.collapsed, id)}

  @doc "Shows the children of the item with `id`."
  @spec expand(t(), term()) :: t()
  def expand(%__MODULE__{} = state, id),
    do: %{state | collapsed: MapSet.delete(state.collapsed, id)}

  @doc "Hides the children of every item that has some."
  @spec collapse_all(t(), [Item.t()]) :: t()
  def collapse_all(%__MODULE__{} = state, items) do
    %{state | collapsed: MapSet.new(parent_ids(items))}
  end

  @doc "Shows every item's children."
  @spec expand_all(t()) :: t()
  def expand_all(%__MODULE__{} = state), do: %{state | collapsed: MapSet.new()}

  @doc """
  The usual Left key: folds the selected item when its children show,
  else selects its parent.
  """
  @spec collapse_or_select_parent(t(), [Item.t()]) :: t()
  def collapse_or_select_parent(%__MODULE__{} = state, items) do
    state = sync(state, items)

    case selected_item(state, items) do
      nil ->
        state

      %Item{children: [_ | _], id: id} = _item ->
        if collapsed?(state, id), do: select_parent(state, items), else: collapse(state, id)

      _leaf ->
        select_parent(state, items)
    end
  end

  @doc """
  The usual Right key: unfolds the selected item when its children are
  hidden, else selects its first child.
  """
  @spec expand_or_select_child(t(), [Item.t()]) :: t()
  def expand_or_select_child(%__MODULE__{} = state, items) do
    state = sync(state, items)

    case selected_item(state, items) do
      %Item{children: [first | _], id: id} ->
        if collapsed?(state, id),
          do: expand(state, id),
          else: sync(select(state, first.id), items)

      _ ->
        state
    end
  end

  @doc "Selects the parent of the selected item, when it has one."
  @spec select_parent(t(), [Item.t()]) :: t()
  def select_parent(%__MODULE__{} = state, items) do
    case path(items, state.selected) do
      [_ | _] = ancestors -> sync(select(state, List.last(ancestors)), items)
      _ -> state
    end
  end

  @doc "The id of the parent of the item with `id`, or `nil` at the top level (or when absent)."
  @spec parent([Item.t()], term()) :: term() | nil
  def parent(items, id) do
    case path(items, id) do
      [_ | _] = ancestors -> List.last(ancestors)
      _ -> nil
    end
  end

  @doc false
  def find(items, id) do
    Enum.find_value(items, fn item ->
      if item.id == id, do: item, else: find(item.children, id)
    end)
  end

  # The ids from the top level down to the item's parent; [] at the top
  # level, nil when the item is not in the tree.
  defp path(items, id) do
    Enum.find_value(items, fn item ->
      cond do
        item.id == id -> []
        sub = path(item.children, id) -> [item.id | sub]
        true -> nil
      end
    end)
  end

  defp visible_ancestor(items, id, rows) do
    visible = MapSet.new(rows, &elem(&1, 0).id)

    case path(items, id) do
      nil -> nil
      ancestors -> ancestors |> Enum.reverse() |> Enum.find(&MapSet.member?(visible, &1))
    end
  end

  defp parent_ids(items) do
    Enum.flat_map(items, fn
      %Item{children: []} -> []
      %Item{id: id, children: children} -> [id | parent_ids(children)]
    end)
  end

  defp select_index(state, [], _index), do: %{state | selected: nil, index: 0}

  defp select_index(state, rows, index) do
    index = index |> max(0) |> min(length(rows) - 1)
    %{state | selected: row_id(rows, index), index: index}
  end

  defp row_id(rows, index), do: rows |> Enum.at(index) |> elem(0) |> Map.fetch!(:id)
end

defmodule Elui.Widgets.Tree do
  @moduledoc """
  A tree of foldable items, one row each, indented by depth, with a fold
  marker before every item that has children. Like `tui-tree-widget`'s
  `Tree` for Ratatui, but its state keeps the *collapsed* items, so a tree
  starts out expanded.

  Render it with `Elui.StatefulWidget.render/4` and an
  `Elui.Widgets.Tree.State`, which moves and folds with the items it is
  given. With `wrap: true`, a long label wraps under itself instead of
  being cut off, for narrow panels. `hit/4` turns a mouse position into a
  row or a fold-marker click; `label_area/4` gives the rectangle of an
  item's label, for drawing an inline editor over it. `prune/2` keeps the
  items that match and their ancestors, for filtering.

  ## Example

      items = [
        Tree.Item.new(:inbox, "Inbox", [Tree.Item.new(1, "write the parser")]),
        Tree.Item.new(:vibex, "vibex")
      ]

      tree = Tree.new(items, highlight_style: [bg: :blue], wrap: true)
      state = Tree.State.new() |> Tree.State.select_first(items)

      {buffer, state} = Elui.StatefulWidget.render(tree, area, buffer, state)
  """

  alias Elui.Buffer
  alias Elui.Layout.Rect
  alias Elui.Style
  alias Elui.Text
  alias Elui.Text.Width
  alias Elui.Widgets.{Block, Paragraph}
  alias Elui.Widgets.Tree.{Item, State}

  @symbols %{expanded: "▾ ", collapsed: "▸ ", leaf: "  "}

  defstruct items: [],
            block: nil,
            style: %Style{},
            highlight_style: %Style{},
            marker_style: %Style{},
            highlight_symbol: "",
            indent: 2,
            symbols: @symbols,
            wrap: false

  @type t :: %__MODULE__{}

  @doc """
  Creates a tree from `Elui.Widgets.Tree.Item`s.

  Options: `:block`, `:style`, `:highlight_style` (the selected row,
  drawn over it as ratatui's `List` does: its colours win over the
  label's own, its modifiers add to them), `:marker_style` (fold markers), `:highlight_symbol` (before the
  selected row), `:indent` (columns per level, default 2), `:symbols` (a
  map or keyword with `:expanded`, `:collapsed` and `:leaf` markers,
  default `"▾ "`, `"▸ "` and `"  "`), and `:wrap` (wrap long labels).
  """
  @spec new([Item.t()], Keyword.t()) :: t()
  def new(items, opts \\ []) do
    %__MODULE__{
      items: items,
      block: Keyword.get(opts, :block),
      style: Style.to_style(Keyword.get(opts, :style)),
      highlight_style: Style.to_style(Keyword.get(opts, :highlight_style)),
      marker_style: Style.to_style(Keyword.get(opts, :marker_style)),
      highlight_symbol: Keyword.get(opts, :highlight_symbol, ""),
      indent: max(Keyword.get(opts, :indent, 2), 0),
      symbols: Map.merge(@symbols, Map.new(Keyword.get(opts, :symbols, %{}))),
      wrap: Keyword.get(opts, :wrap, false)
    }
  end

  @doc """
  Keeps the items for which `fun` is true, and the ancestors of those
  items, so a filtered tree still shows where each match sits. An item
  that is kept keeps only its children that are kept.
  """
  @spec prune([Item.t()], (Item.t() -> as_boolean(term()))) :: [Item.t()]
  def prune(items, fun) do
    Enum.flat_map(items, fn item ->
      children = prune(item.children, fun)
      if children != [] or fun.(item), do: [%{item | children: children}], else: []
    end)
  end

  @doc """
  What is at `{x, y}` in a tree rendered in `area` with `state` (the state
  rendering returned): `{:toggle, id}` on the fold marker of an item with
  children, `{:row, id}` elsewhere on a row, `nil` off the rows.
  """
  @spec hit(t(), Rect.t(), State.t(), {non_neg_integer(), non_neg_integer()}) ::
          {:toggle, term()} | {:row, term()} | nil
  def hit(%__MODULE__{} = tree, %Rect{} = area, %State{} = state, {x, y}) do
    {_offset, rows} = layout(tree, inner(tree, area), state)

    Enum.find_value(rows, fn row ->
      cond do
        y < row.y or y >= row.y + row.height ->
          nil

        row.item.children != [] and x >= row.marker_x and x < row.label_x ->
          {:toggle, row.item.id}

        true ->
          {:row, row.item.id}
      end
    end)
  end

  @doc """
  The rectangle of the label of the item with `id` (its first row, from
  where the label starts to the right edge) in a tree rendered in `area`
  with `state`, or `nil` when that item's row is not on screen.
  """
  @spec label_area(t(), Rect.t(), State.t(), term()) :: Rect.t() | nil
  def label_area(%__MODULE__{} = tree, %Rect{} = area, %State{} = state, id) do
    {_offset, rows} = layout(tree, inner(tree, area), state)

    Enum.find_value(rows, fn row ->
      if row.item.id == id, do: Rect.new(row.label_x, row.y, row.label_width, 1)
    end)
  end

  @doc false
  def render_into(%__MODULE__{} = tree, area, buffer, %State{} = state) do
    buffer = Buffer.set_style(buffer, area, tree.style)
    {inner, buffer} = Block.render_with_block(tree.block, area, buffer)
    state = State.sync(state, tree.items)

    if Rect.empty?(inner) do
      {buffer, state}
    else
      {offset, rows} = layout(tree, inner, state)
      buffer = Enum.reduce(rows, buffer, &render_row(&2, tree, &1, inner, state))
      {buffer, %{state | offset: offset}}
    end
  end

  defp inner(%__MODULE__{block: nil}, area), do: area
  defp inner(%__MODULE__{block: block}, area), do: Block.inner(block, area)

  # The rows on screen, each with its place: the scroll offset that keeps
  # the selection in view, then as many rows from there as fit.
  defp layout(tree, inner, state) do
    symbol_width = Width.of(tree.highlight_symbol)
    marker_width = tree.symbols |> Map.values() |> Enum.map(&Width.of/1) |> Enum.max()

    rows =
      tree.items
      |> State.rows(state)
      |> Enum.map(fn {item, depth} ->
        marker_x = inner.x + symbol_width + depth * tree.indent
        label_x = min(marker_x + marker_width, Rect.right(inner))
        label_width = Rect.right(inner) - label_x

        %{
          item: item,
          depth: depth,
          marker_x: marker_x,
          label_x: label_x,
          label_width: label_width
        }
      end)
      |> Enum.map(&Map.put(&1, :height, row_height(tree, &1)))

    selected =
      if state.selected == nil,
        do: nil,
        else: Enum.find_index(rows, &(&1.item.id == state.selected))

    offset = offset(state.offset, selected, Enum.map(rows, & &1.height), inner.height)

    {_, on_screen} =
      rows
      |> Enum.drop(offset)
      |> Enum.reduce_while({inner.y, []}, fn row, {y, acc} ->
        if y >= Rect.bottom(inner) do
          {:halt, {y, acc}}
        else
          height = min(row.height, Rect.bottom(inner) - y)
          {:cont, {y + row.height, [%{row | height: height} |> Map.put(:y, y) | acc]}}
        end
      end)

    {offset, Enum.reverse(on_screen)}
  end

  defp row_height(%{wrap: true}, %{label_width: width} = row) when width > 0 do
    row.item.label |> Paragraph.new(wrap: [trim: true]) |> Paragraph.line_count(width) |> max(1)
  end

  defp row_height(_tree, row), do: max(Text.height(row.item.label), 1)

  # The first row to draw: unchanged while the selected row fits below it,
  # moved just enough to bring the selected row into view otherwise.
  defp offset(offset, nil, heights, _height), do: min(offset, max(length(heights) - 1, 0))

  defp offset(offset, selected, heights, height) do
    from = min(offset, selected)

    from..selected//1
    |> Enum.find(selected, fn candidate ->
      heights |> Enum.slice(candidate..selected//1) |> Enum.sum() <= height
    end)
  end

  defp render_row(buffer, tree, row, inner, state) do
    selected? = row.item.id == state.selected
    row_style = if selected?, do: tree.highlight_style, else: %Style{}

    buffer =
      if selected?,
        do:
          Buffer.set_style(buffer, Rect.new(inner.x, row.y, inner.width, row.height), row_style),
        else: buffer

    buffer =
      if selected? and tree.highlight_symbol != "" do
        buffer
        |> Buffer.set_stringn(inner.x, row.y, tree.highlight_symbol, inner.width, row_style)
        |> elem(0)
      else
        buffer
      end

    marker =
      cond do
        row.item.children == [] -> tree.symbols.leaf
        State.collapsed?(state, row.item.id) -> tree.symbols.collapsed
        true -> tree.symbols.expanded
      end

    buffer =
      if row.marker_x < Rect.right(inner) do
        marker_style = Style.patch(tree.marker_style, row_style)

        buffer
        |> Buffer.set_stringn(
          row.marker_x,
          row.y,
          marker,
          Rect.right(inner) - row.marker_x,
          marker_style
        )
        |> elem(0)
      else
        buffer
      end

    buffer =
      if row.label_width > 0 do
        label = row.item.label |> Text.patch_style(row.item.style) |> Text.patch_style(row_style)
        paragraph = Paragraph.new(label, wrap: if(tree.wrap, do: [trim: true]), style: row_style)

        Elui.Widget.render(
          paragraph,
          Rect.new(row.label_x, row.y, row.label_width, row.height),
          buffer
        )
      else
        buffer
      end

    # Over the label, so a label coloured like the highlight's background
    # still reads on the selected row.
    if selected?,
      do: Buffer.set_style(buffer, Rect.new(inner.x, row.y, inner.width, row.height), row_style),
      else: buffer
  end

  defimpl Elui.Widget do
    def render(tree, area, buffer) do
      {buffer, _state} = Elui.Widgets.Tree.render_into(tree, area, buffer, %State{})
      buffer
    end
  end

  defimpl Elui.StatefulWidget do
    def render(tree, area, buffer, state) do
      Elui.Widgets.Tree.render_into(tree, area, buffer, state)
    end
  end
end

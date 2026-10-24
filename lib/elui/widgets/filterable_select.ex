defmodule Elui.Widgets.FilterableSelect.State do
  @moduledoc """
  Filter string, selection, and item list for `Elui.Widgets.FilterableSelect`.

  Each item is `%{label: String.t(), value: term()}`. Binary items are
  normalized so `label` and `value` are the same string.

  ## Matching

  `matcher: :substring` (the default) keeps items whose label contains the
  filter, ignoring case and the filter's surrounding spaces, in the order
  given. `matcher: :fuzzy` matches the
  way `Elui.Fuzzy` does (fzf-style: characters in order, every word, smart
  case) and orders the items best first.

  ## Creating

  With `create: true`, a filter that names no item exactly (ignoring case
  and surrounding spaces) adds one more row after the matches: Enter on it
  answers `{:create, text}`, so a picker can offer "pick one, or make a new
  one" (a tag, a project, a label).
  """

  defstruct items: [], filter: "", selected: 0, limit: nil, matcher: :substring, create: false

  @type item :: %{label: String.t(), value: term()}
  @type t :: %__MODULE__{
          items: [item()],
          filter: String.t(),
          selected: non_neg_integer(),
          limit: pos_integer() | nil,
          matcher: :substring | :fuzzy,
          create: boolean()
        }

  @typedoc "What `handle_key/2` asks the app to do."
  @type action :: :continue | {:confirm, term()} | {:create, String.t()} | :cancel | :noop

  @doc """
  Creates filter and selection state for the supplied items.

  Options: `:filter`, `:selected`, `:limit`, `:matcher` (`:substring` or
  `:fuzzy`), and `:create` (offer a row that creates the filter's text).
  """
  @spec new([term()], Keyword.t()) :: t()
  def new(items \\ [], opts \\ []) do
    %__MODULE__{
      items: Enum.map(items, &normalize/1),
      filter: Keyword.get(opts, :filter, ""),
      selected: Keyword.get(opts, :selected, 0),
      limit: Keyword.get(opts, :limit),
      matcher: Keyword.get(opts, :matcher, :substring),
      create: Keyword.get(opts, :create, false)
    }
    |> clamp_selected()
  end

  @doc "Replaces the available items and clamps the current selection."
  @spec set_items(t(), [term()]) :: t()
  def set_items(%__MODULE__{} = state, items) do
    %{state | items: Enum.map(items, &normalize/1)} |> clamp_selected()
  end

  @doc "Items matching the current filter (and optional limit)."
  @spec filtered(t()) :: [item()]
  def filtered(%__MODULE__{} = state) do
    state |> matches() |> Enum.map(&elem(&1, 0))
  end

  @doc """
  Items matching the current filter (and optional limit), each with the
  byte offsets of the label's matched characters, for highlighting:
  `[{item, positions}]`. Positions are empty when nothing was typed, or
  when folding the label's case changed its byte layout.
  """
  @spec matches(t()) :: [{item(), [non_neg_integer()]}]
  def matches(%__MODULE__{matcher: :fuzzy} = state) do
    items = List.to_tuple(state.items)
    labels = Enum.map(state.items, & &1.label)

    state.filter
    |> Elui.Fuzzy.filter(Elui.Fuzzy.prepare(labels))
    |> Enum.map(fn {index, positions} ->
      item = elem(items, index)
      {item, if(same_layout?(state.filter, item.label), do: positions, else: [])}
    end)
    |> maybe_limit(state.limit)
  end

  def matches(%__MODULE__{} = state) do
    needle = state.filter |> String.trim() |> String.downcase()

    state.items
    |> Enum.flat_map(fn %{label: label} = item ->
      folded = String.downcase(label)

      cond do
        needle == "" -> [{item, []}]
        String.contains?(folded, needle) -> [{item, substring_positions(label, folded, needle)}]
        true -> []
      end
    end)
    |> maybe_limit(state.limit)
  end

  @doc """
  The text the create row would create, or `nil` when there is no create
  row: `create` is off, nothing was typed, or an item already has that
  label (ignoring case and surrounding spaces).
  """
  @spec create_text(t()) :: String.t() | nil
  def create_text(%__MODULE__{create: true} = state) do
    text = String.trim(state.filter)
    folded = String.downcase(text)

    cond do
      text == "" -> nil
      Enum.any?(state.items, &(String.downcase(String.trim(&1.label)) == folded)) -> nil
      true -> text
    end
  end

  def create_text(%__MODULE__{}), do: nil

  @doc "Whether the create row is the selected row."
  @spec create_selected?(t()) :: boolean()
  def create_selected?(%__MODULE__{} = state) do
    create_text(state) != nil and state.selected == length(filtered(state))
  end

  @doc "Returns the selected filtered item, or `nil` when no item (or the create row) is selected."
  @spec selected_item(t()) :: item() | nil
  def selected_item(%__MODULE__{} = state) do
    Enum.at(filtered(state), state.selected)
  end

  @doc "Returns the selected filtered value, or `nil` when no item matches."
  @spec selected_value(t()) :: term() | nil
  def selected_value(%__MODULE__{} = state) do
    case selected_item(state) do
      nil -> nil
      %{value: value} -> value
    end
  end

  @doc """
  Applies a keyboard event.

  Returns `{state, action}` where `action` is `:continue`,
  `{:confirm, value}`, `{:create, text}` (Enter on the create row),
  `:cancel`, or `:noop`.

  Up/Down, Ctrl-P/Ctrl-N and Ctrl-K/Ctrl-J move the selection; every
  printable character, `j` and `k` included, goes into the filter.
  """
  @spec handle_key(t(), term()) :: {t(), action()}
  def handle_key(%__MODULE__{} = state, {:key, :esc, _modifiers}) do
    {state, :cancel}
  end

  def handle_key(%__MODULE__{} = state, {:key, :enter, _modifiers}) do
    cond do
      create_selected?(state) -> {state, {:create, create_text(state)}}
      item = selected_item(state) -> {state, {:confirm, item.value}}
      true -> {state, :noop}
    end
  end

  def handle_key(%__MODULE__{} = state, {:key, :down, _modifiers}),
    do: {move(state, 1), :continue}

  def handle_key(%__MODULE__{} = state, {:key, :up, _modifiers}), do: {move(state, -1), :continue}

  def handle_key(%__MODULE__{} = state, {:key, {:char, char}, modifiers})
      when char in ["n", "j"] and is_list(modifiers) do
    if :ctrl in modifiers, do: {move(state, 1), :continue}, else: type(state, char, modifiers)
  end

  def handle_key(%__MODULE__{} = state, {:key, {:char, char}, modifiers})
      when char in ["p", "k"] and is_list(modifiers) do
    if :ctrl in modifiers, do: {move(state, -1), :continue}, else: type(state, char, modifiers)
  end

  def handle_key(%__MODULE__{} = state, {:key, :backspace, _modifiers}) do
    filter = String.slice(state.filter, 0, max(String.length(state.filter) - 1, 0))
    {%{state | filter: filter} |> clamp_selected(), :continue}
  end

  def handle_key(%__MODULE__{} = state, {:key, :space, _modifiers}) do
    {%{state | filter: state.filter <> " "} |> clamp_selected(), :continue}
  end

  def handle_key(%__MODULE__{} = state, {:key, {:char, char}, modifiers})
      when is_binary(char) and is_list(modifiers) do
    type(state, char, modifiers)
  end

  def handle_key(state, _event), do: {state, :noop}

  # A character typed with Ctrl or Alt is a command the select does not
  # know, not text.
  defp type(state, char, modifiers) do
    if Enum.any?(modifiers, &(&1 in [:ctrl, :alt])) do
      {state, :noop}
    else
      {%{state | filter: state.filter <> char} |> clamp_selected(), :continue}
    end
  end

  defp move(state, delta) do
    case row_count(state) do
      0 -> %{state | selected: 0}
      count -> %{state | selected: Integer.mod(state.selected + delta, count)}
    end
  end

  defp clamp_selected(state) do
    selected =
      case row_count(state) do
        0 -> 0
        count -> min(max(state.selected, 0), count - 1)
      end

    %{state | selected: selected}
  end

  # The matches, plus the create row when there is one.
  defp row_count(state) do
    length(filtered(state)) + if(create_text(state), do: 1, else: 0)
  end

  # The start of every grapheme inside the first occurrence of `needle` in
  # the folded label, when folding kept the label's byte layout.
  defp substring_positions(label, folded, needle) do
    if byte_size(label) == byte_size(folded) do
      {start, length} = :binary.match(folded, needle)

      label
      |> grapheme_offsets()
      |> Enum.filter(&(&1 >= start and &1 < start + length))
    else
      []
    end
  end

  defp grapheme_offsets(text) do
    text
    |> String.graphemes()
    |> Enum.map_reduce(0, fn g, offset -> {offset, offset + byte_size(g)} end)
    |> elem(0)
  end

  # Fuzzy positions point into the case-folded label when the query has no
  # capital letter; they fit the label itself only when folding kept its
  # byte layout.
  defp same_layout?(filter, label) do
    filter != String.downcase(filter) or byte_size(label) == byte_size(String.downcase(label))
  end

  defp maybe_limit(items, nil), do: items
  defp maybe_limit(items, limit) when is_integer(limit) and limit > 0, do: Enum.take(items, limit)

  defp normalize(item) when is_binary(item), do: %{label: item, value: item}

  defp normalize(%{label: label} = item) when is_binary(label) do
    %{label: label, value: Map.get(item, :value, label)}
  end

  defp normalize(other) do
    label = to_string(other)
    %{label: label, value: other}
  end
end

defmodule Elui.Widgets.FilterableSelect do
  @moduledoc """
  Filterable select list for modal pickers. Apps supply items; the widget
  owns filtering, selection, and rendering inside a centered modal.

  With a `:match_style`, the characters the filter matched are drawn in
  it; with `State.new(items, create: true)`, the create row is drawn after
  the matches, labelled by `:create_label`.
  """

  alias Elui.Frame
  alias Elui.Style
  alias Elui.Text.{Line, Span}
  alias Elui.Widgets.Block
  alias Elui.Widgets.FilterableSelect.State
  alias Elui.Widgets.List, as: UiList
  alias Elui.Widgets.Modal

  defstruct block: nil,
            style: %Style{},
            highlight_style: %Style{},
            match_style: nil,
            highlight_symbol: "> ",
            empty_label: "(no matches)",
            create_label: nil,
            horizontal: :content,
            vertical: :content,
            min_width: 24,
            max_width_percentage: 70,
            max_visible_items: 12

  @type t :: %__MODULE__{}

  @doc """
  Creates a filterable select.

  Options: `:block`, `:style`, `:highlight_style`, `:match_style` (style
  for the matched characters; none by default), `:highlight_symbol`,
  `:empty_label`, `:create_label` (a function from the text to create to
  the create row's label; default `+ create "TEXT"`), `:horizontal`,
  `:vertical` (modal size constraints or `:content`), `:min_width`,
  `:max_width_percentage`, and `:max_visible_items`.
  """
  @spec new(Keyword.t()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      block: Keyword.get(opts, :block),
      style: Style.to_style(Keyword.get(opts, :style)),
      highlight_style: Style.to_style(Keyword.get(opts, :highlight_style)),
      match_style:
        case Keyword.get(opts, :match_style) do
          nil -> nil
          style -> Style.to_style(style)
        end,
      highlight_symbol: Keyword.get(opts, :highlight_symbol, "> "),
      empty_label: Keyword.get(opts, :empty_label, "(no matches)"),
      create_label: Keyword.get(opts, :create_label, &default_create_label/1),
      horizontal: Keyword.get(opts, :horizontal, :content),
      vertical: Keyword.get(opts, :vertical, :content),
      min_width: max(Keyword.get(opts, :min_width, 24), 1),
      max_width_percentage: Keyword.get(opts, :max_width_percentage, 70),
      max_visible_items: max(Keyword.get(opts, :max_visible_items, 12), 1)
    }
  end

  @doc "Renders the select as a centered modal. Returns `{frame, state}`."
  @spec render_modal(Frame.t(), t(), State.t()) :: {Frame.t(), State.t()}
  def render_modal(%Frame{} = frame, %__MODULE__{} = select, %State{} = state) do
    {rows, labels} = rows(select, state)

    list =
      UiList.new(rows,
        block: select.block,
        style: select.style,
        highlight_style: select.highlight_style,
        highlight_symbol: select.highlight_symbol
      )

    {horizontal, vertical} = modal_constraints(select, labels, Frame.area(frame))

    Modal.render_stateful(frame, list, UiList.State.new(selected: state.selected),
      horizontal: horizontal,
      vertical: vertical
    )
    |> then(fn {frame, _list_state} -> {frame, state} end)
  end

  # The list's rows (lines, matches highlighted) and their plain labels
  # (for sizing the modal).
  defp rows(select, state) do
    matches = State.matches(state)

    create =
      case State.create_text(state) do
        nil -> []
        text -> [select.create_label.(text)]
      end

    case {matches, create} do
      {[], []} ->
        {[select.empty_label], [select.empty_label]}

      _ ->
        lines = Enum.map(matches, fn {item, positions} -> line(item.label, positions, select) end)
        labels = Enum.map(matches, fn {item, _} -> item.label end)
        {lines ++ create, labels ++ create}
    end
  end

  defp line(label, [], _select), do: label
  defp line(label, _positions, %{match_style: nil}), do: label

  defp line(label, positions, %{match_style: style}) do
    matched = MapSet.new(positions)

    label
    |> String.graphemes()
    |> Enum.map_reduce(0, fn g, offset ->
      {{g, MapSet.member?(matched, offset)}, offset + byte_size(g)}
    end)
    |> elem(0)
    |> Enum.chunk_by(&elem(&1, 1))
    |> Enum.map(fn [{_, matched?} | _] = chunk ->
      text = Enum.map_join(chunk, &elem(&1, 0))
      if matched?, do: Span.styled(text, style), else: Span.raw(text)
    end)
    |> Line.new()
  end

  defp default_create_label(text), do: ~s(+ create "#{text}")

  defp modal_constraints(select, labels, area) do
    horizontal =
      case select.horizontal do
        :content ->
          label_width = labels |> Enum.map(&display_width/1) |> Enum.max(fn -> 0 end)
          content_width = label_width + display_width(select.highlight_symbol)
          {content_overhead, title_outer_width} = block_widths(select.block)
          cap = max(div(area.width * select.max_width_percentage, 100), 1)

          width =
            content_width
            |> Kernel.+(content_overhead)
            |> max(title_outer_width)
            |> max(select.min_width)
            |> min(cap)
            |> min(area.width)

          {:length, width}

        constraint ->
          constraint
      end

    vertical =
      case select.vertical do
        :content ->
          height = labels |> length() |> min(select.max_visible_items) |> Kernel.+(2)
          {:length, min(height, area.height)}

        constraint ->
          constraint
      end

    {horizontal, vertical}
  end

  defp block_widths(nil), do: {0, 0}

  defp block_widths(%Block{} = block) do
    border_width = Enum.count([:left, :right], &(&1 in block.borders))
    content_overhead = border_width + block.padding[:left] + block.padding[:right]

    title_width =
      (block.titles_top ++ block.titles_bottom)
      |> Enum.map(&Line.width/1)
      |> Enum.max(fn -> 0 end)

    {content_overhead, title_width + border_width}
  end

  defp display_width(text), do: text |> Line.raw() |> Line.width()
end

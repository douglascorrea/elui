defmodule Elui.Widgets.FilterableSelect.State do
  @moduledoc """
  Filter string, selection, and item list for `Elui.Widgets.FilterableSelect`.

  Each item is `%{label: String.t(), value: term()}`. Binary items are
  normalized so `label` and `value` are the same string.
  """

  defstruct items: [], filter: "", selected: 0, limit: nil

  @type item :: %{label: String.t(), value: term()}
  @type t :: %__MODULE__{
          items: [item()],
          filter: String.t(),
          selected: non_neg_integer(),
          limit: pos_integer() | nil
        }

  @spec new([term()], Keyword.t()) :: t()
  def new(items \\ [], opts \\ []) do
    %__MODULE__{
      items: Enum.map(items, &normalize/1),
      filter: Keyword.get(opts, :filter, ""),
      selected: Keyword.get(opts, :selected, 0),
      limit: Keyword.get(opts, :limit)
    }
    |> clamp_selected()
  end

  @spec set_items(t(), [term()]) :: t()
  def set_items(%__MODULE__{} = state, items) do
    %{state | items: Enum.map(items, &normalize/1)} |> clamp_selected()
  end

  @doc "Items matching the current filter (and optional limit)."
  @spec filtered(t()) :: [item()]
  def filtered(%__MODULE__{} = state) do
    needle = String.downcase(state.filter)

    state.items
    |> Enum.filter(fn %{label: label} ->
      needle == "" or String.contains?(String.downcase(label), needle)
    end)
    |> maybe_limit(state.limit)
  end

  @spec selected_item(t()) :: item() | nil
  def selected_item(%__MODULE__{} = state) do
    Enum.at(filtered(state), state.selected)
  end

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
  `{:confirm, value}`, `:cancel`, or `:noop`.
  """
  @spec handle_key(t(), term()) ::
          {t(), :continue | {:confirm, term()} | :cancel | :noop}
  def handle_key(%__MODULE__{} = state, {:key, :esc, _modifiers}) do
    {state, :cancel}
  end

  def handle_key(%__MODULE__{} = state, {:key, :enter, _modifiers}) do
    case selected_value(state) do
      nil -> {state, :noop}
      value -> {state, {:confirm, value}}
    end
  end

  def handle_key(%__MODULE__{} = state, {:key, key, _modifiers})
      when key in [:down, {:char, "j"}] do
    {move(state, 1), :continue}
  end

  def handle_key(%__MODULE__{} = state, {:key, key, _modifiers})
      when key in [:up, {:char, "k"}] do
    {move(state, -1), :continue}
  end

  def handle_key(%__MODULE__{} = state, {:key, :backspace, _modifiers}) do
    filter = String.slice(state.filter, 0, max(String.length(state.filter) - 1, 0))
    {%{state | filter: filter} |> clamp_selected(), :continue}
  end

  def handle_key(%__MODULE__{} = state, {:key, :space, _modifiers}) do
    {%{state | filter: state.filter <> " "} |> clamp_selected(), :continue}
  end

  def handle_key(%__MODULE__{} = state, {:key, {:char, char}, _modifiers})
      when is_binary(char) do
    {%{state | filter: state.filter <> char} |> clamp_selected(), :continue}
  end

  def handle_key(state, _event), do: {state, :noop}

  defp move(state, delta) do
    count = length(filtered(state))

    cond do
      count == 0 ->
        %{state | selected: 0}

      true ->
        %{state | selected: Integer.mod(state.selected + delta, count)}
    end
  end

  defp clamp_selected(state) do
    count = length(filtered(state))

    selected =
      cond do
        count == 0 -> 0
        true -> min(max(state.selected, 0), count - 1)
      end

    %{state | selected: selected}
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
  """

  alias Elui.Frame
  alias Elui.Style
  alias Elui.Widgets.FilterableSelect.State
  alias Elui.Widgets.List, as: UiList
  alias Elui.Widgets.Modal

  defstruct block: nil,
            style: %Style{},
            highlight_style: %Style{},
            highlight_symbol: "> ",
            empty_label: "(no matches)",
            horizontal: :content,
            vertical: :content,
            min_width: 24,
            max_width_percentage: 70,
            max_visible_items: 12

  @type t :: %__MODULE__{}

  @doc """
  Creates a filterable select.

  Options: `:block`, `:style`, `:highlight_style`, `:highlight_symbol`,
  `:empty_label`, `:horizontal`, `:vertical` (modal size constraints or
  `:content`), `:min_width`, `:max_width_percentage`, and
  `:max_visible_items`.
  """
  @spec new(Keyword.t()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      block: Keyword.get(opts, :block),
      style: Style.to_style(Keyword.get(opts, :style)),
      highlight_style: Style.to_style(Keyword.get(opts, :highlight_style)),
      highlight_symbol: Keyword.get(opts, :highlight_symbol, "> "),
      empty_label: Keyword.get(opts, :empty_label, "(no matches)"),
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
    labels =
      case State.filtered(state) do
        [] -> [select.empty_label]
        items -> Enum.map(items, & &1.label)
      end

    list =
      UiList.new(labels,
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

  defp modal_constraints(select, labels, area) do
    horizontal =
      case select.horizontal do
        :content ->
          content_width = labels |> Enum.map(&String.length/1) |> Enum.max(fn -> 0 end)
          cap = max(div(area.width * select.max_width_percentage, 100), 1)
          width = (content_width + 4) |> max(select.min_width) |> min(cap) |> min(area.width)
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
end

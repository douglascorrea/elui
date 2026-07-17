defmodule Elui.Widgets.TextArea.State do
  @moduledoc """
  Editable text and cursor for `Elui.Widgets.TextArea`.

  `cursor` is a UTF-8 grapheme offset into `text` (0..grapheme_count).
  """

  defstruct text: "", cursor: 0, scroll: 0

  @type t :: %__MODULE__{
          text: String.t(),
          cursor: non_neg_integer(),
          scroll: non_neg_integer()
        }

  @doc "Creates text editing state, placing the cursor at the end by default."
  @spec new(Keyword.t()) :: t()
  def new(opts \\ []) do
    text = Keyword.get(opts, :text, "") || ""
    graphemes = String.graphemes(text)
    cursor = Keyword.get(opts, :cursor, length(graphemes))
    cursor = cursor |> max(0) |> min(length(graphemes))

    %__MODULE__{
      text: text,
      cursor: cursor,
      scroll: Keyword.get(opts, :scroll, 0)
    }
  end

  @doc "Replaces the text, resets scroll, and moves the cursor to the end."
  @spec set_text(t(), String.t()) :: t()
  def set_text(%__MODULE__{} = state, text) when is_binary(text) do
    graphemes = String.graphemes(text)
    %{state | text: text, cursor: length(graphemes), scroll: 0}
  end

  @doc "Applies a keyboard event. Returns `{state, :continue | :noop}`."
  @spec handle_key(t(), term()) :: {t(), :continue | :noop}
  def handle_key(%__MODULE__{} = state, {:key, :enter, _modifiers}) do
    {insert(state, "\n"), :continue}
  end

  def handle_key(%__MODULE__{} = state, {:key, :backspace, _modifiers}) do
    {delete_before(state), :continue}
  end

  def handle_key(%__MODULE__{} = state, {:key, :left, _modifiers}) do
    {%{state | cursor: max(state.cursor - 1, 0)}, :continue}
  end

  def handle_key(%__MODULE__{} = state, {:key, :right, _modifiers}) do
    max_cursor = length(String.graphemes(state.text))
    {%{state | cursor: min(state.cursor + 1, max_cursor)}, :continue}
  end

  def handle_key(%__MODULE__{} = state, {:key, :up, _modifiers}) do
    {move_vertical(state, -1), :continue}
  end

  def handle_key(%__MODULE__{} = state, {:key, :down, _modifiers}) do
    {move_vertical(state, 1), :continue}
  end

  def handle_key(%__MODULE__{} = state, {:key, :space, _modifiers}) do
    {insert(state, " "), :continue}
  end

  def handle_key(%__MODULE__{} = state, {:key, {:char, char}, []}) when is_binary(char) do
    {insert(state, char), :continue}
  end

  def handle_key(state, _event), do: {state, :noop}

  defp insert(state, chunk) do
    graphemes = String.graphemes(state.text)
    {before, after_part} = Enum.split(graphemes, state.cursor)
    inserted = String.graphemes(chunk)
    text = Enum.join(before ++ inserted ++ after_part, "")
    %{state | text: text, cursor: state.cursor + length(inserted)}
  end

  defp delete_before(%{cursor: 0} = state), do: state

  defp delete_before(state) do
    graphemes = String.graphemes(state.text)
    {before, after_part} = Enum.split(graphemes, state.cursor)
    before = Enum.drop(before, -1)
    text = Enum.join(before ++ after_part, "")
    %{state | text: text, cursor: state.cursor - 1}
  end

  defp move_vertical(state, delta) do
    lines = String.split(state.text, "\n")
    {line_index, col} = cursor_line_col(state.text, state.cursor)
    target = line_index + delta

    cond do
      target < 0 ->
        %{state | cursor: 0}

      target >= length(lines) ->
        %{state | cursor: length(String.graphemes(state.text))}

      true ->
        target_line = Enum.at(lines, target)
        col = min(col, length(String.graphemes(target_line)))
        prefix = lines |> Enum.take(target) |> Enum.join("\n")
        offset = if prefix == "", do: 0, else: length(String.graphemes(prefix)) + 1
        %{state | cursor: offset + col}
    end
  end

  @doc false
  @spec cursor_line_col(String.t(), non_neg_integer()) ::
          {non_neg_integer(), non_neg_integer()}
  def cursor_line_col(text, cursor) do
    graphemes = String.graphemes(text)
    {before, _} = Enum.split(graphemes, cursor)
    before_text = Enum.join(before, "")
    lines = String.split(before_text, "\n")
    line_index = length(lines) - 1
    col = length(String.graphemes(List.last(lines) || ""))
    {line_index, col}
  end
end

defmodule Elui.Widgets.TextArea do
  @moduledoc """
  Multiline editable text field with a cursor. Apps decide submit keys;
  `Enter` inserts a newline.
  """

  alias Elui.Buffer
  alias Elui.Layout.Rect
  alias Elui.Style
  alias Elui.Widgets.Block
  alias Elui.Widgets.TextArea.State

  defstruct block: nil,
            style: %Style{},
            cursor_style: %Style{},
            placeholder: ""

  @type t :: %__MODULE__{}

  @doc """
  Creates a text area.

  Options: `:block`, `:style`, `:cursor_style`, `:placeholder`.
  """
  @spec new(Keyword.t()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      block: Keyword.get(opts, :block),
      style: Style.to_style(Keyword.get(opts, :style)),
      cursor_style: Style.to_style(Keyword.get(opts, :cursor_style, bg: :blue, fg: :white)),
      placeholder: Keyword.get(opts, :placeholder, "")
    }
  end

  @doc false
  def render_into(%__MODULE__{} = field, area, buffer, %State{} = state) do
    buffer = Buffer.set_style(buffer, area, field.style)
    {inner, buffer} = Block.render_with_block(field.block, area, buffer)

    if Rect.empty?(inner) do
      {buffer, state}
    else
      display = if state.text == "", do: field.placeholder, else: state.text
      lines = String.split(display, "\n")
      {line_index, col} = State.cursor_line_col(state.text, state.cursor)
      scroll = clamp_scroll(state.scroll, line_index, inner.height)
      state = %{state | scroll: scroll}

      buffer =
        lines
        |> Enum.with_index()
        |> Enum.drop(scroll)
        |> Enum.take(inner.height)
        |> Enum.reduce(buffer, fn {line, index}, buf ->
          y = inner.y + (index - scroll)
          text = String.slice(line, 0, max(inner.width, 0))

          style =
            if state.text == "", do: Style.patch(field.style, fg: :dark_gray), else: field.style

          Buffer.set_string(buf, inner.x, y, String.pad_trailing(text, inner.width), style)
        end)

      buffer =
        if state.text == "" do
          cursor_grapheme = field.placeholder |> String.graphemes() |> List.first() || " "
          Buffer.set_string(buffer, inner.x, inner.y, cursor_grapheme, field.cursor_style)
        else
          cursor_y = inner.y + (line_index - scroll)

          if cursor_y >= inner.y and cursor_y < Rect.bottom(inner) do
            row = Enum.at(lines, line_index) || ""
            ch = String.at(row, col) || " "
            Buffer.set_string(buffer, inner.x + col, cursor_y, ch, field.cursor_style)
          else
            buffer
          end
        end

      {buffer, state}
    end
  end

  defp clamp_scroll(scroll, line_index, height) when height > 0 do
    cond do
      line_index < scroll -> line_index
      line_index >= scroll + height -> line_index - height + 1
      true -> max(scroll, 0)
    end
  end

  defp clamp_scroll(scroll, _line_index, _height), do: max(scroll, 0)

  defimpl Elui.Widget do
    def render(field, area, buffer) do
      {buffer, _state} =
        Elui.Widgets.TextArea.render_into(field, area, buffer, Elui.Widgets.TextArea.State.new())

      buffer
    end
  end

  defimpl Elui.StatefulWidget do
    def render(field, area, buffer, state) do
      Elui.Widgets.TextArea.render_into(field, area, buffer, state)
    end
  end
end

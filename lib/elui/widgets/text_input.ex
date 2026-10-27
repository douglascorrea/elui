defmodule Elui.Widgets.TextInput.State do
  @moduledoc """
  The text, cursor and scroll of an `Elui.Widgets.TextInput`.

  `cursor` and `offset` (the first grapheme shown, once the text is wider
  than the field) count graphemes, so accented letters, emoji and wide
  characters move and delete as one.
  """

  defstruct text: "", cursor: 0, offset: 0

  @type t :: %__MODULE__{text: String.t(), cursor: non_neg_integer(), offset: non_neg_integer()}

  @typedoc "What `handle_key/2` asks the app to do."
  @type action :: :continue | {:submit, String.t()} | :cancel | :noop

  @doc "Creates the state. Options: `:text`, and `:cursor` (default: the end)."
  @spec new(Keyword.t()) :: t()
  def new(opts \\ []) do
    text = Keyword.get(opts, :text, "") || ""
    count = length(String.graphemes(text))
    %__MODULE__{text: text, cursor: opts |> Keyword.get(:cursor, count) |> max(0) |> min(count)}
  end

  @doc "Replaces the text and puts the cursor at its end."
  @spec set_text(t(), String.t()) :: t()
  def set_text(%__MODULE__{} = state, text), do: %{new(text: text) | offset: state.offset}

  @doc """
  Handles a key event. Returns `{state, action}`, where `action` is
  `:continue` (the text or cursor changed), `{:submit, text}` (Enter),
  `:cancel` (Esc) or `:noop`.

  Editing keys follow readline and macOS text fields:
  - **Moving:** Left/Right, Home/End, Ctrl-A/Ctrl-E, Ctrl-B/Ctrl-F, and by
    word with Alt or Ctrl plus Left/Right, or Alt-B/Alt-F.
  - **Deleting:** Backspace and Delete (or Ctrl-H/Ctrl-D), a word back
    with Ctrl-W or Alt-Backspace, a word forward with Alt-D, to the start
    with Ctrl-U, and to the end with Ctrl-K.
  """
  @spec handle_key(t(), term()) :: {t(), action()}
  def handle_key(%__MODULE__{} = state, {:key, :enter, _mods}), do: {state, {:submit, state.text}}
  def handle_key(%__MODULE__{} = state, {:key, :esc, _mods}), do: {state, :cancel}
  def handle_key(%__MODULE__{} = state, {:key, :space, _mods}), do: insert(state, " ")

  def handle_key(%__MODULE__{} = state, {:key, :backspace, mods}) do
    if :alt in mods or :ctrl in mods,
      do: cut(state, word_back(state), state.cursor),
      else: cut(state, state.cursor - 1, state.cursor)
  end

  def handle_key(%__MODULE__{} = state, {:key, :delete, _mods}),
    do: cut(state, state.cursor, state.cursor + 1)

  def handle_key(%__MODULE__{} = state, {:key, :left, mods}) do
    if :alt in mods or :ctrl in mods,
      do: move(state, word_back(state)),
      else: move(state, state.cursor - 1)
  end

  def handle_key(%__MODULE__{} = state, {:key, :right, mods}) do
    if :alt in mods or :ctrl in mods,
      do: move(state, word_forward(state)),
      else: move(state, state.cursor + 1)
  end

  def handle_key(%__MODULE__{} = state, {:key, :home, _mods}), do: move(state, 0)
  def handle_key(%__MODULE__{} = state, {:key, :end, _mods}), do: move(state, count(state))

  def handle_key(%__MODULE__{} = state, {:key, {:char, char}, mods}) do
    cond do
      :ctrl in mods -> control(state, char)
      :alt in mods -> meta(state, char)
      true -> insert(state, char)
    end
  end

  def handle_key(%__MODULE__{} = state, _event), do: {state, :noop}

  defp control(state, char) do
    case String.downcase(char) do
      "a" -> move(state, 0)
      "e" -> move(state, count(state))
      "b" -> move(state, state.cursor - 1)
      "f" -> move(state, state.cursor + 1)
      "h" -> cut(state, state.cursor - 1, state.cursor)
      "d" -> cut(state, state.cursor, state.cursor + 1)
      "w" -> cut(state, word_back(state), state.cursor)
      "u" -> cut(state, 0, state.cursor)
      "k" -> cut(state, state.cursor, count(state))
      _ -> {state, :noop}
    end
  end

  defp meta(state, char) do
    case String.downcase(char) do
      "b" -> move(state, word_back(state))
      "f" -> move(state, word_forward(state))
      "d" -> cut(state, state.cursor, word_forward(state))
      _ -> {state, :noop}
    end
  end

  defp insert(state, text) do
    {before, rest} = String.split_at(state.text, state.cursor)
    added = length(String.graphemes(text))
    {%{state | text: before <> text <> rest, cursor: state.cursor + added}, :continue}
  end

  defp cut(state, from, to) do
    from = max(from, 0)
    to = min(to, count(state))

    if from >= to do
      {state, :noop}
    else
      graphemes = String.graphemes(state.text)
      text = Enum.join(Enum.take(graphemes, from) ++ Enum.drop(graphemes, to))
      {%{state | text: text, cursor: from}, :continue}
    end
  end

  defp move(state, to) do
    to = to |> max(0) |> min(count(state))
    if to == state.cursor, do: {state, :noop}, else: {%{state | cursor: to}, :continue}
  end

  # The start of the word before the cursor, skipping the spaces before it.
  defp word_back(state) do
    state.text
    |> String.graphemes()
    |> Enum.take(state.cursor)
    |> Enum.reverse()
    |> Enum.drop_while(&blank?/1)
    |> Enum.drop_while(&(not blank?(&1)))
    |> length()
  end

  # The end of the word after the cursor, skipping the spaces before it.
  defp word_forward(state) do
    rest = state.text |> String.graphemes() |> Enum.drop(state.cursor)
    {spaces, rest} = Enum.split_while(rest, &blank?/1)
    word = Enum.take_while(rest, &(not blank?(&1)))
    state.cursor + length(spaces) + length(word)
  end

  defp blank?(grapheme), do: String.trim(grapheme) == ""

  defp count(state), do: length(String.graphemes(state.text))
end

defmodule Elui.Widgets.TextInput do
  @moduledoc """
  A one-line text field: a prompt, the text, and a cursor drawn as a
  reversed cell. A text wider than the field scrolls sideways, so the
  cursor is always in view. Keys go to `Elui.Widgets.TextInput.State`.

  Render it with `Elui.StatefulWidget.render/4`, which returns the state
  with its scroll updated. `cursor_position/3` gives the cursor's cell, for
  apps that would rather show the terminal's own cursor
  (`Elui.Frame.set_cursor_position/2`).

  ## Example

      input = TextInput.new(prompt: "> ", placeholder: "new todo")
      state = TextInput.State.new(text: "write the parser")

      {state, action} = TextInput.State.handle_key(state, {:key, {:char, "s"}, []})
      {buffer, state} = Elui.StatefulWidget.render(input, area, buffer, state)
  """

  alias Elui.Buffer
  alias Elui.Layout.Rect
  alias Elui.Style
  alias Elui.Text.Width
  alias Elui.Widgets.TextInput.State

  defstruct style: %Style{},
            cursor_style: %Style{},
            prompt: "",
            prompt_style: %Style{},
            placeholder: "",
            placeholder_style: %Style{}

  @type t :: %__MODULE__{}

  @doc """
  Creates a text field. Options: `:style` (the text), `:cursor_style`
  (default reversed), `:prompt` (default none) and `:prompt_style`,
  `:placeholder` (shown while the text is empty) and `:placeholder_style`
  (default dim).
  """
  @spec new(Keyword.t()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      style: Style.to_style(Keyword.get(opts, :style)),
      cursor_style: Style.to_style(Keyword.get(opts, :cursor_style, add_modifier: [:reversed])),
      prompt: Keyword.get(opts, :prompt, ""),
      prompt_style: Style.to_style(Keyword.get(opts, :prompt_style)),
      placeholder: Keyword.get(opts, :placeholder, ""),
      placeholder_style:
        Style.to_style(Keyword.get(opts, :placeholder_style, add_modifier: [:dim]))
    }
  end

  @doc """
  The state scrolled so its cursor fits in `area`. The field shows the
  graphemes from `offset` on, and always keeps its last cell for a cursor
  at the end. It scrolls only as far as the cursor needs, and back when
  the text would leave room unused.
  """
  @spec scroll(t(), Rect.t(), State.t()) :: State.t()
  def scroll(%__MODULE__{} = input, %Rect{} = area, %State{} = state) do
    room = area.width - Width.of(input.prompt)
    widths = state.text |> String.graphemes() |> Enum.map(&Width.grapheme_width/1)
    cursor = Enum.at(widths, state.cursor, 1)
    fits? = fn start -> width(widths, start, state.cursor) + cursor <= room end

    # Forward until the cursor fits, from where the field was.
    start = min(state.offset, state.cursor)
    start = Enum.find(start..state.cursor//1, state.cursor, fits?)

    # Back while everything from there to the end, and a cell after it, still fits.
    start = Enum.find(0..start//1, start, &(width(widths, &1, length(widths)) + 1 <= room))

    %{state | offset: start}
  end

  defp width(widths, from, to), do: widths |> Enum.slice(from, to - from) |> Enum.sum()

  @doc "The cell the cursor is drawn in, or nil when the field has no room."
  @spec cursor_position(t(), Rect.t(), State.t()) :: {non_neg_integer(), non_neg_integer()} | nil
  def cursor_position(%__MODULE__{} = input, %Rect{} = area, %State{} = state) do
    state = scroll(input, area, state)
    x = area.x + Width.of(input.prompt) + Width.of(shown_before_cursor(state))
    if area.height > 0 and x < Rect.right(area), do: {x, area.y}
  end

  @doc false
  def render_into(%__MODULE__{} = input, %Rect{} = area, %Buffer{} = buffer, %State{} = state) do
    state = scroll(input, area, state)

    if area.height <= 0 or area.width <= 0 do
      {buffer, state}
    else
      y = area.y

      {buffer, x} =
        Buffer.set_stringn(buffer, area.x, y, input.prompt, area.width, input.prompt_style)

      room = Rect.right(area) - x

      buffer =
        cond do
          room <= 0 ->
            buffer

          state.text == "" ->
            {buffer, _} = Buffer.set_stringn(buffer, x, y, " ", 1, input.cursor_style)

            buffer
            |> Buffer.set_stringn(x + 1, y, input.placeholder, room - 1, input.placeholder_style)
            |> elem(0)

          true ->
            draw_text(buffer, input, state, x, y, room)
        end

      {buffer, state}
    end
  end

  defp draw_text(buffer, input, state, x, y, room) do
    graphemes = state.text |> String.graphemes() |> Enum.drop(state.offset)
    before = shown_before_cursor(state)
    {under, after_} = graphemes |> Enum.drop(state.cursor - state.offset) |> Enum.split(1)

    {buffer, cx} = Buffer.set_stringn(buffer, x, y, before, room, input.style)
    cursor = if under == [], do: " ", else: hd(under)

    {buffer, ax} =
      Buffer.set_stringn(
        buffer,
        cx,
        y,
        cursor,
        x + room - cx,
        Style.patch(input.style, input.cursor_style)
      )

    {buffer, _} = Buffer.set_stringn(buffer, ax, y, Enum.join(after_), x + room - ax, input.style)
    buffer
  end

  defp shown_before_cursor(state) do
    state.text
    |> String.graphemes()
    |> Enum.slice(state.offset, state.cursor - state.offset)
    |> Enum.join()
  end

  defimpl Elui.StatefulWidget do
    def render(input, area, buffer, state) do
      Elui.Widgets.TextInput.render_into(input, area, buffer, state)
    end
  end
end

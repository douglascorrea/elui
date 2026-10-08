defmodule Elui.Widgets.TextAreaTest do
  use ExUnit.Case, async: true

  alias Elui.Backend.Test, as: TestBackend
  alias Elui.{Buffer, Frame, Terminal}
  alias Elui.Widgets.{Block, Modal, TextArea}
  alias Elui.Widgets.TextArea.State

  test "State inserts characters, newlines, and backspaces" do
    state = State.new()
    {state, :continue} = State.handle_key(state, {:key, {:char, "h"}, []})
    {state, :continue} = State.handle_key(state, {:key, {:char, "i"}, []})
    {state, :continue} = State.handle_key(state, {:key, :enter, []})
    {state, :continue} = State.handle_key(state, {:key, {:char, "!"}, []})
    assert state.text == "hi\n!"
    {state, :continue} = State.handle_key(state, {:key, :backspace, []})
    assert state.text == "hi\n"
  end

  test "Modal clears a centered area and TextArea renders body text" do
    state = State.new(text: "Hello\nworld")
    field = TextArea.new(block: Block.bordered(title: "Compose"))

    terminal = test_terminal(40, 12)

    {terminal, state} =
      Terminal.draw(terminal, fn frame ->
        Modal.render_stateful(frame, field, state, vertical: {:length, 6})
      end)

    screen = terminal |> lines() |> Enum.join("\n")

    assert screen =~ "Compose"
    assert screen =~ "Hello"
    assert screen =~ "world"
    assert state.text == "Hello\nworld"
  end

  test "Modal preserves a themed surface behind border and content cells" do
    state = State.new(text: "Readable")

    field =
      TextArea.new(
        style: [fg: :black],
        block: Block.bordered(title: "Compose", border_style: [fg: :blue])
      )

    terminal = test_terminal(40, 12)

    {terminal, _state} =
      Terminal.draw(terminal, fn frame ->
        frame =
          Frame.render_widget(
            frame,
            Block.new(style: [fg: :black, bg: :white]),
            Frame.area(frame)
          )

        Modal.render_stateful(frame, field, state, vertical: {:length, 6})
      end)

    buffer = terminal.previous_buffer
    border = Buffer.get(buffer, 6, 3)
    content = Buffer.get(buffer, 7, 4)

    assert border.style.fg == :blue
    assert border.style.bg == :white
    assert content.style.fg == :black
    assert content.style.bg == :white
  end

  test "an empty TextArea keeps every placeholder grapheme visible under the cursor" do
    state = State.new()
    field = TextArea.new(placeholder: "Write your post…")
    terminal = test_terminal(30, 3)

    {terminal, _state} =
      Terminal.draw(terminal, fn frame ->
        Frame.render_stateful_widget(frame, field, Frame.area(frame), state)
      end)

    assert terminal |> lines() |> hd() |> String.trim_trailing() == "Write your post…"
  end

  test "word wrapping keeps complete words and the cursor inside the TextArea" do
    state = State.new(text: "alpha beta gamma delta")
    field = TextArea.new(wrap: :word, cursor_style: [bg: :red])
    terminal = test_terminal(12, 4)

    {terminal, state} =
      Terminal.draw(terminal, fn frame ->
        Frame.render_stateful_widget(frame, field, Frame.area(frame), state)
      end)

    [first, second, third, fourth] = lines(terminal)
    assert String.trim_trailing(first) == "alpha beta"
    assert String.trim_trailing(second) == "gamma delta"
    assert String.trim_trailing(third) == ""
    assert String.trim_trailing(fourth) == ""
    assert state.scroll == 0

    buffer = terminal |> Terminal.backend_state() |> TestBackend.buffer()
    cursor = Buffer.get(buffer, 11, 1)
    assert cursor.style.bg == :red
  end

  test "word wrapping breaks oversized tokens without crossing widget bounds" do
    state = State.new(text: String.duplicate("x", 23))
    field = TextArea.new(wrap: :word)
    terminal = test_terminal(8, 3)

    {terminal, _state} =
      Terminal.draw(terminal, fn frame ->
        Frame.render_stateful_widget(frame, field, Frame.area(frame), state)
      end)

    assert Enum.map(lines(terminal), &String.trim_trailing/1) == [
             "xxxxxxxx",
             "xxxxxxxx",
             "xxxxxxx"
           ]

    assert Enum.all?(lines(terminal), &(String.length(&1) == 8))
  end

  test "word wrapping scrolls by visual row and preserves Unicode cursor width" do
    state = State.new(text: "one two three four five café")
    field = TextArea.new(wrap: :word, cursor_style: [bg: :magenta])
    terminal = test_terminal(9, 2)

    {terminal, state} =
      Terminal.draw(terminal, fn frame ->
        Frame.render_stateful_widget(frame, field, Frame.area(frame), state)
      end)

    assert state.scroll > 0
    assert terminal |> lines() |> Enum.join("\n") =~ "café"

    buffer = terminal |> Terminal.backend_state() |> TestBackend.buffer()

    assert Enum.any?(buffer.cells, fn {{x, y}, cell} ->
             x in 0..8 and y in 0..1 and cell.style.bg == :magenta
           end)
  end

  test "word wrapping hides boundary whitespace instead of creating a whitespace-only row" do
    state = State.new(text: "hello world")
    field = TextArea.new(wrap: true)
    terminal = test_terminal(5, 3)

    {terminal, state} =
      Terminal.draw(terminal, fn frame ->
        Frame.render_stateful_widget(frame, field, Frame.area(frame), state)
      end)

    assert Enum.map(lines(terminal), &String.trim_trailing/1) == ["hello", "world", ""]
    assert state.visual_wrap == :word
  end

  test "Up and Down follow wrapped visual rows after rendering establishes the width" do
    state = State.new(text: "one two three")
    field = TextArea.new(wrap: :word)
    terminal = test_terminal(5, 4)

    {_terminal, state} =
      Terminal.draw(terminal, fn frame ->
        Frame.render_stateful_widget(frame, field, Frame.area(frame), state)
      end)

    assert state.cursor == 13
    {state, :continue} = State.handle_key(state, {:key, :up, []})
    assert state.cursor == 8
    {state, :continue} = State.handle_key(state, {:key, :down, []})
    assert state.cursor == 13
  end

  test "full-width Unicode keeps a visible cursor at the widget boundary" do
    state = State.new(text: "界")
    field = TextArea.new(wrap: :word, cursor_style: [bg: :cyan])
    terminal = test_terminal(2, 2)

    {terminal, _state} =
      Terminal.draw(terminal, fn frame ->
        Frame.render_stateful_widget(frame, field, Frame.area(frame), state)
      end)

    buffer = terminal |> Terminal.backend_state() |> TestBackend.buffer()
    assert Buffer.get(buffer, 0, 0).symbol == "界"
    assert Buffer.get(buffer, 0, 1).style.bg == :cyan
  end

  test "an exact-width physical line does not add a blank row before a newline" do
    state = State.new(text: "hello\nx", cursor: 5)
    field = TextArea.new(wrap: :word, cursor_style: [bg: :yellow])
    terminal = test_terminal(5, 3)

    {terminal, _state} =
      Terminal.draw(terminal, fn frame ->
        Frame.render_stateful_widget(frame, field, Frame.area(frame), state)
      end)

    assert Enum.map(lines(terminal), &String.trim_trailing/1) == ["hello", "x", ""]

    buffer = terminal |> Terminal.backend_state() |> TestBackend.buffer()
    assert Buffer.get(buffer, 4, 0).symbol == "o"
    assert Buffer.get(buffer, 4, 0).style.bg == :yellow
  end

  test "a full-width glyph keeps its complete cursor style before a hard newline" do
    state = State.new(text: "界\nx", cursor: 1)
    field = TextArea.new(wrap: :word, cursor_style: [bg: :cyan])
    terminal = test_terminal(2, 2)

    {terminal, _state} =
      Terminal.draw(terminal, fn frame ->
        Frame.render_stateful_widget(frame, field, Frame.area(frame), state)
      end)

    buffer = terminal.previous_buffer
    assert Buffer.get(buffer, 0, 0).symbol == "界"
    assert Buffer.get(buffer, 0, 0).style.bg == :cyan
    assert Buffer.get(buffer, 1, 0).skip
    assert terminal |> lines() |> Enum.at(1) |> String.trim_trailing() == "x"
  end

  test "State edits a combining Unicode grapheme atomically" do
    {state, :continue} = State.handle_key(State.new(), {:key, {:char, "é"}, []})
    assert state.text == "é"
    assert state.cursor == 1

    {state, :continue} = State.handle_key(state, {:key, :backspace, []})
    assert state.text == ""
    assert state.cursor == 0
  end

  test "TextArea rejects unsupported wrap modes instead of silently disabling wrapping" do
    assert_raise ArgumentError, ~r/TextArea :wrap/, fn -> TextArea.new(wrap: :character) end
  end

  defp test_terminal(width, height) do
    Terminal.new(
      backend: TestBackend,
      backend_opts: [width: width, height: height]
    )
  end

  defp lines(terminal), do: terminal |> Terminal.backend_state() |> TestBackend.to_lines()
end

defmodule Elui.Widgets.TextAreaTest do
  use ExUnit.Case, async: true

  alias Elui.Buffer
  alias Elui.Layout.Rect
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

    area = Rect.new(0, 0, 40, 12)
    frame = %Elui.Frame{buffer: Buffer.empty(area), area: area, cursor_position: nil}
    {frame, state} = Modal.render_stateful(frame, field, state, vertical: {:length, 6})
    screen = Buffer.to_lines(frame.buffer) |> Enum.join("\n")

    assert screen =~ "Compose"
    assert screen =~ "Hello"
    assert screen =~ "world"
    assert state.text == "Hello\nworld"
  end

  test "an empty TextArea keeps every placeholder grapheme visible under the cursor" do
    state = State.new()
    field = TextArea.new(placeholder: "Write your post…")
    area = Rect.new(0, 0, 30, 3)

    {buffer, _state} =
      Elui.StatefulWidget.render(field, area, Buffer.empty(area), state)

    assert buffer |> Buffer.to_lines() |> hd() |> String.trim_trailing() == "Write your post…"
  end
end

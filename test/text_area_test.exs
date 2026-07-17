defmodule Elui.Widgets.TextAreaTest do
  use ExUnit.Case, async: true

  alias Elui.Backend.Test, as: TestBackend
  alias Elui.{Frame, Terminal}
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

  defp test_terminal(width, height) do
    Terminal.new(
      backend: TestBackend,
      backend_opts: [width: width, height: height]
    )
  end

  defp lines(terminal), do: terminal |> Terminal.backend_state() |> TestBackend.to_lines()
end

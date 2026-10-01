defmodule Elui.TerminalTest do
  use ExUnit.Case, async: true

  alias Elui.Backend.Test, as: TestBackend
  alias Elui.Frame
  alias Elui.Terminal
  alias Elui.Widgets.Paragraph

  defp new_terminal(width, height) do
    Terminal.new(backend: TestBackend, backend_opts: [width: width, height: height])
  end

  test "draw renders widgets to the backend" do
    terminal = new_terminal(10, 2)

    {terminal, _} =
      Terminal.draw(terminal, fn frame ->
        Frame.render_widget(frame, Paragraph.new("Hello"), Frame.area(frame))
      end)

    lines = TestBackend.to_lines(Terminal.backend_state(terminal))
    assert hd(lines) == "Hello     "
  end

  test "consecutive draws only flush the diff" do
    terminal = new_terminal(5, 1)

    draw = fn terminal, text ->
      Terminal.draw(terminal, fn frame ->
        Frame.render_widget(frame, Paragraph.new(text), Frame.area(frame))
      end)
    end

    {terminal, _} = draw.(terminal, "aaaa")
    {terminal, _} = draw.(terminal, "aaba")

    lines = TestBackend.to_lines(Terminal.backend_state(terminal))
    assert hd(lines) == "aaba "
  end

  test "frame can return a result" do
    terminal = new_terminal(5, 1)

    {_terminal, result} =
      Terminal.draw(terminal, fn frame -> {frame, :my_result} end)

    assert result == :my_result
  end

  test "cursor position is forwarded to the backend" do
    terminal = new_terminal(10, 2)

    {terminal, _} =
      Terminal.draw(terminal, fn frame ->
        Frame.set_cursor_position(frame, {3, 1})
      end)

    backend = Terminal.backend_state(terminal)
    assert backend.cursor == {3, 1}
    assert backend.cursor_visible
  end

  test "raw overlays reach the backend and clear on the next frame" do
    terminal = new_terminal(10, 2)

    {terminal, _} =
      Terminal.draw(terminal, fn frame ->
        Frame.put_overlay(frame, 2, 1, ["raw", "-bytes"])
      end)

    assert Terminal.backend_state(terminal).overlays == [{2, 1, ["raw", "-bytes"]}]

    {terminal, _} = Terminal.draw(terminal, & &1)
    assert Terminal.backend_state(terminal).overlays == []
  end
end

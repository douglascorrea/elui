defmodule Elui.Widgets.ParagraphTest do
  use ExUnit.Case, async: true

  alias Elui.Backend.Test, as: TestBackend
  alias Elui.{Buffer, Frame, Terminal}
  alias Elui.Text.{Line, Span}
  alias Elui.Widgets.Paragraph

  test "visible glyphs inherit Paragraph style while Span style remains more specific" do
    terminal =
      Terminal.new(
        backend: TestBackend,
        backend_opts: [width: 8, height: 2]
      )

    paragraph =
      Paragraph.new(Line.new(["Base ", Span.styled("Span", fg: :cyan)]),
        style: [fg: :magenta, bg: :black, add_modifier: [:bold]]
      )

    {terminal, _result} =
      Terminal.draw(terminal, fn frame ->
        Frame.render_widget(frame, paragraph, Frame.area(frame))
      end)

    buffer = terminal |> Terminal.backend_state() |> TestBackend.buffer()
    base = Buffer.get(buffer, 0, 0)
    specific = Buffer.get(buffer, 5, 0)

    assert base.symbol == "B"
    assert base.style.fg == :magenta
    assert base.style.bg == :black
    assert :bold in base.style.add_modifier

    assert specific.symbol == "S"
    assert specific.style.fg == :cyan
    assert specific.style.bg == :black
    assert :bold in specific.style.add_modifier
  end
end

defmodule Elui.Widgets.MermaidTest do
  use ExUnit.Case, async: true

  alias Elui.Backend.Test, as: TestBackend
  alias Elui.{Frame, Terminal}
  alias Elui.Widgets.{Block, Mermaid}

  defp draw(widget, width, height) do
    terminal = Terminal.new(backend: TestBackend, backend_opts: [width: width, height: height])

    {terminal, _} =
      Terminal.draw(terminal, fn frame ->
        Frame.render_widget(frame, widget, Frame.area(frame))
      end)

    terminal
    |> Terminal.backend_state()
    |> TestBackend.to_lines()
    |> Enum.map(&String.trim_trailing/1)
  end

  test "draws the diagram in a block" do
    widget = Mermaid.new("graph LR\n  A --> B", block: Block.bordered())

    assert draw(widget, 17, 5) == [
             "┌───────────────┐",
             "│┌───┐    ┌───┐ │",
             "││ A ├───►│ B │ │",
             "│└───┘    └───┘ │",
             "└───────────────┘"
           ]
  end

  test "scrolls by rows and columns" do
    widget = Mermaid.new("graph TD\n  A --> B", scroll: {3, 2})
    assert draw(widget, 5, 3) == ["│", "▼", "──┐"]
    assert Mermaid.new("graph TD\n  A --> B", scroll: 6) |> draw(5, 2) == ["│ B │", "└───┘"]
  end

  test "fits the diagram to the area's width" do
    widget = Mermaid.new("graph LR\n  A[a long label to wrap] --> B[another long label]")
    assert Mermaid.line_count(widget, 200) < Mermaid.line_count(widget, 40)
    assert widget |> Mermaid.to_text(40) |> Elui.Text.width() <= 40
  end

  test "shows source it can't draw under the error" do
    assert draw(Mermaid.new("graph TD\n  A -->"), 40, 3) == [
             "Mermaid: line 2: expected a node after a",
             "graph TD",
             "  A -->"
           ]
  end

  test "shows the source of a diagram too large to draw" do
    source =
      "flowchart TD\n  T[\"" <>
        Enum.map_join(1..3000, "<br>", fn _ -> "x" end) <>
        "\"] --> " <>
        Enum.map_join(1..150, " & ", &"A#{&1}")

    assert ["Mermaid: the diagram is too large to draw", "flowchart TD" | _] =
             draw(Mermaid.new(source), 60, 3)
  end

  test ":scroll is rows or {rows, columns}" do
    assert_raise ArgumentError, ~r/:scroll must be rows or \{rows, columns\}/, fn ->
      Mermaid.new("graph TD\n A", scroll: -1)
    end
  end
end

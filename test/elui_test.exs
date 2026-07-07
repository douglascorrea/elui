defmodule EluiTest do
  use ExUnit.Case, async: true

  test "hello world renders end to end" do
    terminal = Elui.Terminal.new(backend: Elui.Backend.Test, backend_opts: [width: 20, height: 3])

    {terminal, _} =
      Elui.Terminal.draw(terminal, fn frame ->
        Elui.Frame.render_widget(
          frame,
          Elui.Widgets.Paragraph.new("Hello, world!",
            block: Elui.Widgets.Block.bordered(title: "Greeting")
          ),
          Elui.Frame.area(frame)
        )
      end)

    lines = Elui.Backend.Test.to_lines(Elui.Terminal.backend_state(terminal))

    assert lines == [
             "┌Greeting──────────┐",
             "│Hello, world!     │",
             "└──────────────────┘"
           ]
  end
end

defmodule Elui do
  @moduledoc """
  Elui is a terminal user interface library for Elixir, inspired by
  [ratatui](https://github.com/ratatui/ratatui).

  It follows the same immediate-mode rendering model: on every frame
  you rebuild the whole UI from your state, the library diffs the new
  frame against the previous one and only writes the changed cells to
  the terminal.

  ## Building blocks

    * `Elui.Terminal` / `Elui.Frame` - the draw loop and frame API
    * `Elui.Layout` / `Elui.Layout.Rect` / `Elui.Layout.Constraint` -
      splitting the screen into areas
    * `Elui.Style` / `Elui.Style.Color` - colors and text attributes
    * `Elui.Text` / `Elui.Text.Line` / `Elui.Text.Span` - styled text
    * `Elui.Buffer` - the cell grid widgets render into
    * `Elui.Widget` / `Elui.StatefulWidget` - the rendering protocols
    * `Elui.Backend` - terminal backends (`Elui.Backend.Ansi` for real
      terminals, `Elui.Backend.Test` for tests)
    * `Elui.Input` - raw-mode keyboard events
    * `Elui.App` - an Elm-style run loop

  ## Widgets

  `Elui.Widgets.Block`, `Elui.Widgets.Paragraph`, `Elui.Widgets.List`,
  `Elui.Widgets.Table`, `Elui.Widgets.Tabs`, `Elui.Widgets.Gauge`,
  `Elui.Widgets.LineGauge`, `Elui.Widgets.BarChart`,
  `Elui.Widgets.Sparkline`, `Elui.Widgets.Chart`,
  `Elui.Widgets.Canvas`, `Elui.Widgets.Calendar`,
  `Elui.Widgets.Scrollbar` and `Elui.Widgets.Clear`.

  ## Hello world

      terminal = Elui.Terminal.new()

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

      Elui.Terminal.restore(terminal)

  See the `examples/` directory for complete interactive programs.
  """
end

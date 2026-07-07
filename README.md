# Elui

A terminal user interface (TUI) library for Elixir, inspired by
[ratatui](https://github.com/ratatui/ratatui).

Elui follows the same immediate-mode rendering model as ratatui: on every
frame you rebuild the whole UI from your state; the library diffs the new
frame against the previous one and writes only the changed cells to the
terminal.

```
┌Elui──────────────────────────────────────────┐
│                                              │
│                Hello, world!                 │
│                                              │
│               Press q to quit.               │
│                                              │
└──────────────────────────────────────────────┘
```

## Requirements

- Elixir ~> 1.20 (Erlang/OTP 26+ for built-in raw terminal mode)
- A terminal emulator with ANSI escape sequence support

## Installation

Add `elui` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:elui, "~> 0.1.0"}
  ]
end
```

## Quick start

The fastest way to build an app is the Elm-style `Elui.App` behaviour,
which wires up the terminal, raw-mode keyboard input and a render loop:

```elixir
defmodule Counter do
  @behaviour Elui.App

  alias Elui.Frame
  alias Elui.Widgets.{Block, Paragraph}

  @impl true
  def init(_opts), do: 0

  @impl true
  def update(_count, {:key, {:char, "q"}, _mods}), do: :quit
  def update(count, {:key, :up, _mods}), do: {:ok, count + 1}
  def update(count, {:key, :down, _mods}), do: {:ok, count - 1}
  def update(count, _event), do: {:ok, count}

  @impl true
  def view(count, frame) do
    Frame.render_widget(
      frame,
      Paragraph.new("Count: #{count}\n\n↑/↓ to change, q to quit",
        alignment: :center,
        block: Block.bordered(title: "Counter")
      ),
      Frame.area(frame)
    )
  end
end

Elui.App.run(Counter)
```

You can also drive the terminal manually, exactly like ratatui's
`Terminal::draw`:

```elixir
terminal = Elui.Terminal.new()

{terminal, _} =
  Elui.Terminal.draw(terminal, fn frame ->
    Elui.Frame.render_widget(frame, Elui.Widgets.Paragraph.new("Hello!"), Elui.Frame.area(frame))
  end)

Elui.Terminal.restore(terminal)
```

## Examples

The [`examples/`](examples/) directory contains runnable programs. The
original Elui examples are still useful as small widget-focused entry
points:

| Example | Run with | Shows |
| --- | --- | --- |
| `hello_world.exs` | `mix run examples/hello_world.exs` | Minimal app |
| `layout.exs` | `mix run examples/layout.exs` | Constraints, nested splits, spacing |
| `list.exs` | `mix run examples/list.exs` | Selectable list + scrollbar |
| `table.exs` | `mix run examples/table.exs` | Table with header and row selection |
| `gauges.exs` | `mix run examples/gauges.exs` | Gauge, LineGauge, Sparkline, BarChart |
| `chart.exs` | `mix run examples/chart.exs` | Line/scatter chart with axes and legend |
| `canvas.exs` | `mix run examples/canvas.exs` | Braille canvas with shapes and animation |
| `popup.exs` | `mix run examples/popup.exs` | Clear + centered rect modal |
| `user_input.exs` | `mix run examples/user_input.exs` | Text input with cursor placement |
| `demo.exs` | `mix run examples/demo.exs` | Multi-tab tour of most widgets |
| `beam_lab.exs` | `mix run examples/beam_lab.exs` | Supervisor tree, GenServers, BEAM nodes and an internet event stream |

It also includes Elixir ports of every app under Ratatui's
`examples/apps/` directory:

| Ratatui app | Elui example |
| --- | --- |
| `advanced-widget-impl` | `examples/advanced_widget_impl.exs` |
| `async-github` | `examples/async_github.exs` |
| `calendar-explorer` | `examples/calendar_explorer.exs` |
| `canvas` | `examples/canvas.exs` |
| `chart` | `examples/chart.exs` |
| `color-explorer` | `examples/color_explorer.exs` |
| `colors-rgb` | `examples/colors_rgb.exs` |
| `constraint-explorer` | `examples/constraint_explorer.exs` |
| `constraints` | `examples/constraints.exs` |
| `custom-widget` | `examples/custom_widget.exs` |
| `demo` | `examples/demo.exs` |
| `demo2` | `examples/demo2.exs` |
| `flex` | `examples/flex.exs` |
| `gauge` | `examples/gauge.exs` |
| `hello-world` | `examples/hello_world.exs` |
| `hyperlink` | `examples/hyperlink.exs` |
| `inline` | `examples/inline.exs` |
| `input-form` | `examples/input_form.exs` |
| `minimal` | `examples/minimal.exs` |
| `modifiers` | `examples/modifiers.exs` |
| `mouse-drawing` | `examples/mouse_drawing.exs` |
| `panic` | `examples/panic.exs` |
| `popup` | `examples/popup.exs` |
| `release-header` | `examples/release_header.exs` |
| `scrollbar` | `examples/scrollbar.exs` |
| `table` | `examples/table.exs` |
| `todo-list` | `examples/todo_list.exs` |
| `tracing` | `examples/tracing.exs` |
| `user-input` | `examples/user_input.exs` |
| `volatility-surface` | `examples/volatility_surface.exs` |
| `weather` | `examples/weather.exs` |
| `widget-ref-container` | `examples/widget_ref_container.exs` |

## Feature map (ratatui → Elui)

| ratatui | Elui |
| --- | --- |
| `Terminal` / `Frame` | `Elui.Terminal` / `Elui.Frame` |
| `Backend` (crossterm/termion/termwiz) | `Elui.Backend` behaviour, `Elui.Backend.Ansi` |
| `TestBackend` | `Elui.Backend.Test` |
| `Buffer` / `Cell` | `Elui.Buffer` / `Elui.Buffer.Cell` |
| `Rect`, `Layout`, `Constraint`, `Flex` | `Elui.Layout.Rect`, `Elui.Layout`, `Elui.Layout.Constraint`, `:flex` option |
| `Style`, `Color`, `Modifier`, `Stylize` | `Elui.Style`, `Elui.Style.Color`, fluent helpers on `Elui.Style` |
| `Span`, `Line`, `Text`, `Masked` | `Elui.Text.Span`, `Elui.Text.Line`, `Elui.Text`, `Elui.Text.masked/2` |
| `Widget` / `StatefulWidget` traits | `Elui.Widget` / `Elui.StatefulWidget` protocols |
| `Block` (borders, titles, padding) | `Elui.Widgets.Block` |
| `Paragraph` (wrap, scroll, alignment) | `Elui.Widgets.Paragraph` |
| `List` / `ListState` | `Elui.Widgets.List` / `Elui.Widgets.List.State` |
| `Table` / `TableState` / `Row` | `Elui.Widgets.Table` / `.State` / `.Row` |
| `Tabs` | `Elui.Widgets.Tabs` |
| `Gauge` / `LineGauge` | `Elui.Widgets.Gauge` / `Elui.Widgets.LineGauge` |
| `BarChart` / `Bar` / `BarGroup` | `Elui.Widgets.BarChart` / `.Bar` / `.BarGroup` |
| `Sparkline` | `Elui.Widgets.Sparkline` |
| `Chart` / `Axis` / `Dataset` | `Elui.Widgets.Chart` / `.Axis` / `.Dataset` |
| `Canvas` + shapes (line, rect, circle, points) | `Elui.Widgets.Canvas` + `Elui.Widgets.Canvas.Shapes` |
| `calendar::Monthly` | `Elui.Widgets.Calendar` |
| `Scrollbar` / `ScrollbarState` | `Elui.Widgets.Scrollbar` / `.State` |
| `Clear` | `Elui.Widgets.Clear` |
| `symbols` module | `Elui.Symbols` |
| crossterm key and mouse events | `Elui.Input` (raw mode, parsed key events and SGR mouse capture) |
| hand-written event loop | `Elui.App` behaviour (optional), including tick, resize and app message events |

## Concepts

### Layout

```elixir
alias Elui.Layout

[top, body, bottom] =
  Layout.vertical([{:length, 3}, {:fill, 1}, {:length, 1}])
  |> Layout.split(area)

[left, right] =
  Layout.horizontal([{:percentage, 30}, {:percentage, 70}], spacing: 1)
  |> Layout.split(body)
```

Constraints: `{:length, n}`, `{:percentage, p}`, `{:ratio, num, den}`,
`{:min, n}`, `{:max, n}`, `{:fill, weight}`. Flex modes: `:legacy`,
`:start`, `:end`, `:center`, `:space_between`, `:space_around`,
`:space_evenly`.

### Styling

```elixir
Elui.Style.new(fg: :yellow, bg: :black, add_modifier: [:bold, :italic])
Elui.Style.new(fg: {:rgb, 255, 128, 0})
Elui.Style.new() |> Elui.Style.fg(:red) |> Elui.Style.bold()
```

Most widget options accept either a `%Elui.Style{}` or a plain keyword
list.

### Styled text

```elixir
alias Elui.Text.{Line, Span}

Line.new([
  Span.new("Status: "),
  Span.new("OK", fg: :green, add_modifier: [:bold])
])
```

### Testing your UI

Use `Elui.Backend.Test` to render frames into memory:

```elixir
terminal = Elui.Terminal.new(backend: Elui.Backend.Test, backend_opts: [width: 20, height: 3])
{terminal, _} = Elui.Terminal.draw(terminal, fn frame -> ... end)
Elui.Backend.Test.to_lines(Elui.Terminal.backend_state(terminal))
#=> ["┌Greeting──────────┐", "│Hello, world!     │", "└──────────────────┘"]
```

## License

MIT

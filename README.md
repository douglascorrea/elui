# Elui

Elui is a terminal user interface library for Elixir, inspired by
[Ratatui](https://github.com/ratatui/ratatui).

Website: [elui.sh](https://elui.sh)

It gives Elixir projects an immediate-mode TUI toolkit: rebuild the UI from
your current state on every frame, render widgets into a buffer, and let the
terminal backend write only the changed cells.

```
┌Elui──────────────────────────────────────────┐
│                                              │
│                Hello, world!                 │
│                                              │
│        Immediate-mode terminal UIs           │
│              for Elixir and OTP              │
│                                              │
└──────────────────────────────────────────────┘
```

Elui is early-stage and intentionally small. The core API is already useful
for demos, prototypes, dashboards, CLIs, and experiments, but public API
changes can still happen before a stable release.

## Features

- Immediate-mode rendering with `Elui.Terminal` and `Elui.Frame`
- Ratatui-shaped concepts: buffers, cells, styles, layout, widgets, and
  stateful widgets
- ANSI terminal backend for real terminals and a test backend for assertions
- Elm-style `Elui.App` runner for keyboard, mouse, tick, resize, and process
  message events
- Layout constraints with flex alignment modes
- Styled text, spans, paragraphs, wrapping, scrolling, and alignment
- Widgets for blocks, lists, tables, tabs, gauges, charts, canvas drawing,
  calendars, scrollbars, sparklines, bar charts, and clearing regions
- Semantic themes plus production app primitives for modals, filterable
  selects, multiline editing, toggle matrices, and responsive week layouts
- Raw keyboard input and SGR mouse capture
- Examples that port every app from Ratatui's `examples/apps/`
- OTP-friendly examples that show supervisors, GenServers, BEAM nodes, remote
  nodes, and streamed internet data

## Requirements

- Elixir `~> 1.20`
- Erlang/OTP with ANSI-capable terminal support
- A terminal emulator that supports ANSI escape sequences

## Installation

Until the first Hex release, install directly from GitHub:

```elixir
def deps do
  [
    {:elui, github: "douglascorrea/elui"}
  ]
end
```

After Elui is published to Hex, use the package dependency:

```elixir
def deps do
  [
    {:elui, "~> 0.1.0"}
  ]
end
```

## Quick Start

The easiest way to build an app is the `Elui.App` behaviour. It wires up a
terminal, raw-mode input, resize detection, app messages, and a render loop.

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

If you want full control over the loop, drive the terminal manually:

```elixir
terminal = Elui.Terminal.new()

{terminal, _result} =
  Elui.Terminal.draw(terminal, fn frame ->
    Elui.Frame.render_widget(
      frame,
      Elui.Widgets.Paragraph.new("Hello from Elui!"),
      Elui.Frame.area(frame)
    )
  end)

Elui.Terminal.restore(terminal)
```

## Examples

Run examples from the repository root:

```sh
mix deps.get
mix run examples/demo.exs
```

Useful starting points:

| Example | Command | Shows |
| --- | --- | --- |
| Demo | `mix run examples/demo.exs` | A tour of most widgets |
| Hello world | `mix run examples/hello_world.exs` | Minimal app structure |
| Flex | `mix run examples/flex.exs` | Constraint and flex alignment behavior |
| Mouse drawing | `mix run examples/mouse_drawing.exs` | Mouse input and continuous drawing |
| Async GitHub | `mix run examples/async_github.exs` | Async fetch of Elixir commits |
| Calendar explorer | `mix run examples/calendar_explorer.exs` | Interactive calendar styles and navigation |
| Canvas | `mix run examples/canvas.exs` | Braille canvas shapes and animation |
| Charts | `mix run examples/chart.exs` | Datasets, axes, legends, and plotting |
| Beam Lab | `mix run examples/beam_lab.exs` | Supervisors, GenServers, BEAM nodes, and streamed GitHub events |

Elui also includes Elixir ports of every Ratatui app under
`ratatui/examples/apps/`:

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

## Ratatui Concepts In Elui

| Ratatui | Elui |
| --- | --- |
| `Terminal` / `Frame` | `Elui.Terminal` / `Elui.Frame` |
| `Backend` | `Elui.Backend`, `Elui.Backend.Ansi`, `Elui.Backend.Test` |
| `Buffer` / `Cell` | `Elui.Buffer` / `Elui.Buffer.Cell` |
| `Rect`, `Layout`, `Constraint`, `Flex` | `Elui.Layout.Rect`, `Elui.Layout`, `Elui.Layout.Constraint`, `:flex` |
| `Style`, `Color`, `Modifier` | `Elui.Style`, `Elui.Style.Color` |
| `Span`, `Line`, `Text` | `Elui.Text.Span`, `Elui.Text.Line`, `Elui.Text` |
| `Widget` / `StatefulWidget` traits | `Elui.Widget` / `Elui.StatefulWidget` protocols |
| crossterm input events | `Elui.Input` key and SGR mouse events |
| app event loop | `Elui.App` behaviour |

## Testing UI Code

Use `Elui.Backend.Test` to render frames into memory and assert on plain text:

```elixir
terminal =
  Elui.Terminal.new(
    backend: Elui.Backend.Test,
    backend_opts: [width: 20, height: 3]
  )

{terminal, _} =
  Elui.Terminal.draw(terminal, fn frame ->
    Elui.Frame.render_widget(
      frame,
      Elui.Widgets.Paragraph.new("Hello"),
      Elui.Frame.area(frame)
    )
  end)

Elui.Backend.Test.to_lines(Elui.Terminal.backend_state(terminal))
#=> ["Hello               ", "                    ", "                    "]
```

## Development

```sh
mix deps.get
mix format --check-formatted
mix test
mix hex.audit
mix hex.build --unpack
```

The formatter currently covers `mix.exs`, `.formatter.exs`, `lib/`, and
`test/`. Example scripts are tested for loadability so they keep compiling as
the library evolves.

## Security

Elui renders to terminals. Terminals interpret ANSI, CSI, and OSC control
sequences, so treat untrusted strings with the same care you would use for any
output sink with control syntax.

- Prefer Elui text and widget APIs for ordinary user-visible strings.
- Do not render untrusted raw terminal escape sequences unless that is exactly
  the feature you are building.
- The BEAM Lab example uses a per-run distributed Erlang cookie and prints the
  helper command in the UI. Enabling BEAM distribution is a network boundary;
  only connect nodes you trust.
- Report vulnerabilities using the process in [SECURITY.md](SECURITY.md).

## Contributing

Contributions are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md), open
an issue for larger changes, and keep pull requests focused.

The project follows the [Code of Conduct](CODE_OF_CONDUCT.md).

## License

Elui is released under the [MIT License](LICENSE).

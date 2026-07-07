Code.require_file("support/ratatui_port.exs", __DIR__)

# Release Header demo: terminal-rendered release announcement header.
#
# Run with:
#
#     mix run examples/release_header.exs

defmodule Examples.ReleaseHeader do
  @behaviour Elui.App

  alias Elui.{Frame, Layout}
  alias Elui.Text.{Line, Span}
  alias Elui.Widgets.{Block, Paragraph}

  @impl true
  def init(_opts), do: %{}

  @impl true
  def update(model, event) do
    if Examples.Support.quit?(event), do: :quit, else: {:ok, model}
  end

  @impl true
  def view(_model, frame) do
    [hero, body, footer] =
      Layout.vertical([{:length, 8}, {:fill, 1}, {:length, 1}])
      |> Layout.split(Frame.area(frame))

    hero_text = [
      Line.new("ELUI 0.1.0", style: [fg: :yellow, add_modifier: [:bold]], alignment: :center),
      Line.new("Ratatui-inspired terminal UI for Elixir", alignment: :center),
      Line.new("Immediate-mode rendering, styled buffers, widgets, and examples.", style: [fg: :cyan], alignment: :center)
    ]

    [left, right] =
      Layout.horizontal([{:percentage, 50}, {:fill, 1}], spacing: 1)
      |> Layout.split(body)

    frame =
      Frame.render_widget(
        frame,
        Paragraph.new(hero_text, block: Block.bordered(title: "Release Header", border_type: :double)),
        hero
      )

    frame =
      Examples.Support.render_panel(
        frame,
        left,
        "Highlights",
        [
          Line.new([Span.new("• ", fg: :green), Span.new("Diffed terminal frames")]),
          Line.new([Span.new("• ", fg: :green), Span.new("Layout flex modes")]),
          Line.new([Span.new("• ", fg: :green), Span.new("Core widget set")]),
          Line.new([Span.new("• ", fg: :green), Span.new("Example app ports")])
        ]
      )

    frame =
      Examples.Support.render_panel(
        frame,
        right,
        "Install",
        "Add {:elui, \"~> 0.1.0\"} to deps and build your UI in Elui.App.view/2."
      )

    Examples.Support.render_footer(frame, footer, "q/Esc quit")
  end
end

Examples.Support.run(Examples.ReleaseHeader)

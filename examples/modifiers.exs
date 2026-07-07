Code.require_file("support/ratatui_port.exs", __DIR__)

# Modifiers demo: renders every supported text modifier.
#
# Run with:
#
#     mix run examples/modifiers.exs

defmodule Examples.Modifiers do
  @behaviour Elui.App

  alias Elui.{Frame, Layout}
  alias Elui.Style
  alias Elui.Text.{Line, Span}
  alias Elui.Widgets.{Block, Paragraph}

  @mods Style.modifiers()

  @impl true
  def init(_opts), do: %{selected: 0}

  @impl true
  def update(model, event) do
    cond do
      Examples.Support.quit?(event) -> :quit
      Examples.Support.key?(event, [:down, {:char, "j"}]) -> {:ok, %{model | selected: Examples.Support.cycle(model.selected, 1, length(@mods))}}
      Examples.Support.key?(event, [:up, {:char, "k"}]) -> {:ok, %{model | selected: Examples.Support.cycle(model.selected, -1, length(@mods))}}
      true -> {:ok, model}
    end
  end

  @impl true
  def view(model, frame) do
    [header, body, footer] =
      Layout.vertical([{:length, 2}, {:fill, 1}, {:length, 1}])
      |> Layout.split(Frame.area(frame))

    lines =
      @mods
      |> Enum.with_index()
      |> Enum.map(fn {modifier, i} ->
        marker = if i == model.selected, do: "> ", else: "  "

        Line.new([
          Span.new(marker, fg: :yellow),
          Span.new(String.pad_trailing(to_string(modifier), 16), fg: :cyan),
          Span.new("The quick brown fox", add_modifier: [modifier])
        ])
      end)

    frame =
      Examples.Support.render_header(frame, header, "Modifiers", "j/k select, q quit")

    frame =
      Frame.render_widget(
        frame,
        Paragraph.new(lines, block: Block.bordered(title: "Style.add_modifier")),
        body
      )

    Examples.Support.render_footer(frame, footer, "selected modifier: #{Enum.at(@mods, model.selected)}")
  end
end

Examples.Support.run(Examples.Modifiers)

Code.require_file("support/ratatui_port.exs", __DIR__)

# Color explorer demo: browse named ANSI colors and inspect them as
# foreground/background styles.
#
# Run with:
#
#     mix run examples/color_explorer.exs

defmodule Examples.ColorExplorer do
  @behaviour Elui.App

  alias Elui.{Frame, Layout}
  alias Elui.Text.{Line, Span}
  alias Elui.Widgets.{Block, Paragraph}
  alias Elui.Widgets.List, as: UiList

  @colors Examples.Support.ansi_colors()

  @impl true
  def init(_opts), do: %{selected: 0, list_state: UiList.State.new(selected: 0)}

  @impl true
  def update(model, event) do
    cond do
      Examples.Support.quit?(event) ->
        :quit

      Examples.Support.key?(event, [:down, {:char, "j"}]) ->
        select(model, 1)

      Examples.Support.key?(event, [:up, {:char, "k"}]) ->
        select(model, -1)

      true ->
        {:ok, model}
    end
  end

  @impl true
  def view(model, frame) do
    [header, body, footer] =
      Layout.vertical([{:length, 2}, {:fill, 1}, {:length, 1}])
      |> Layout.split(Frame.area(frame))

    [list_area, swatch_area] =
      Layout.horizontal([{:length, 24}, {:fill, 1}], spacing: 1)
      |> Layout.split(body)

    frame =
      Examples.Support.render_header(frame, header, "Color Explorer", "j/k select, q quit")

    items = Enum.map(@colors, fn {name, color} -> "#{String.pad_trailing(name, 13)} #{inspect(color)}" end)

    {frame, _state} =
      Frame.render_stateful_widget(
        frame,
        UiList.new(items,
          block: Block.bordered(title: "Named colors"),
          highlight_style: [bg: :blue],
          highlight_symbol: "> "
        ),
        list_area,
        model.list_state
      )

    {name, color} = Enum.at(@colors, model.selected)

    lines = [
      Line.new(""),
      Line.new([Span.new("    foreground sample    ", fg: color, add_modifier: [:bold])], alignment: :center),
      Line.new(""),
      Line.new([Span.new("    background sample    ", fg: :black, bg: color, add_modifier: [:bold])], alignment: :center),
      Line.new(""),
      Line.new("Elui color: #{inspect(color)}", alignment: :center)
    ]

    frame =
      Frame.render_widget(
        frame,
        Paragraph.new(lines,
          alignment: :center,
          block: Block.bordered(title: name, border_style: [fg: color])
        ),
        swatch_area
      )

    Examples.Support.render_footer(frame, footer, "colors map to 16-color, indexed and RGB ANSI output")
  end

  defp select(model, delta) do
    selected = Examples.Support.cycle(model.selected, delta, length(@colors))
    {:ok, %{model | selected: selected, list_state: UiList.State.select(model.list_state, selected)}}
  end
end

Examples.Support.run(Examples.ColorExplorer)

Code.require_file("support/ratatui_port.exs", __DIR__)

# Flex demo: switch through Elui layout flex modes.
#
# Run with:
#
#     mix run examples/flex.exs

defmodule Examples.Flex do
  @behaviour Elui.App

  alias Elui.{Frame, Layout}
  alias Elui.Widgets.{Block, Paragraph, Tabs}

  @modes [:legacy, :start, :end, :center, :space_between, :space_around, :space_evenly]

  @impl true
  def init(_opts), do: %{selected: 1}

  @impl true
  def update(model, event) do
    cond do
      Examples.Support.quit?(event) -> :quit
      Examples.Support.key?(event, [:right, {:char, "l"}]) -> {:ok, %{model | selected: Examples.Support.cycle(model.selected, 1, length(@modes))}}
      Examples.Support.key?(event, [:left, {:char, "h"}]) -> {:ok, %{model | selected: Examples.Support.cycle(model.selected, -1, length(@modes))}}
      true -> {:ok, model}
    end
  end

  @impl true
  def view(model, frame) do
    mode = Enum.at(@modes, model.selected)

    [tabs, body, footer] =
      Layout.vertical([{:length, 3}, {:fill, 1}, {:length, 1}])
      |> Layout.split(Frame.area(frame))

    frame =
      Frame.render_widget(
        frame,
        Tabs.new(Enum.map(@modes, &Atom.to_string/1),
          selected: model.selected,
          block: Block.bordered(title: "Flex"),
          highlight_style: [fg: :yellow, add_modifier: [:bold]]
        ),
        tabs
      )

    [horizontal, vertical] =
      Layout.vertical([{:fill, 1}, {:fill, 1}], spacing: 1)
      |> Layout.split(body)

    frame =
      render_flex_row(frame, horizontal, :horizontal, mode)
      |> render_flex_row(vertical, :vertical, mode)

    Examples.Support.render_footer(frame, footer, "h/l switch flex mode, q quit")
  end

  defp render_flex_row(frame, area, direction, mode) do
    layout =
      Layout.new(
        direction: direction,
        constraints: [{:length, 12}, {:length, 10}, {:length, 8}],
        spacing: 1,
        flex: mode
      )

    layout
    |> Layout.split(area)
    |> Enum.with_index()
    |> Enum.reduce(
      Frame.render_widget(frame, Block.bordered(title: "#{direction} / #{mode}"), area),
      fn {rect, i}, acc ->
        Frame.render_widget(
          acc,
          Paragraph.new("item #{i + 1}", alignment: :center, block: Block.bordered(border_style: [fg: palette(i)])),
          rect
        )
      end
    )
  end

  defp palette(i), do: Enum.at([:cyan, :magenta, :green], i)
end

Examples.Support.run(Examples.Flex)

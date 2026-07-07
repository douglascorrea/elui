Code.require_file("support/ratatui_port.exs", __DIR__)

# Constraints demo: static gallery of Length, Percentage, Ratio, Fill,
# Min and Max layout behavior.
#
# Run with:
#
#     mix run examples/constraints.exs

defmodule Examples.Constraints do
  @behaviour Elui.App

  alias Elui.{Frame, Layout}
  alias Elui.Text.Line
  alias Elui.Widgets.{Block, Paragraph, Tabs}

  @tabs [
    {"Length", [[{:length, 20}, {:length, 20}], [{:length, 20}, {:min, 20}], [{:length, 20}, {:max, 20}]]},
    {"Percentage", [[{:percentage, 75}, {:fill, 1}], [{:percentage, 25}, {:fill, 1}], [{:percentage, 50}, {:min, 20}]]},
    {"Ratio", [[{:ratio, 1, 2}, {:ratio, 1, 2}], [{:ratio, 1, 4}, {:ratio, 1, 4}, {:ratio, 1, 4}, {:ratio, 1, 4}]]},
    {"Fill", [[{:fill, 1}, {:fill, 2}, {:fill, 3}], [{:fill, 1}, {:percentage, 50}, {:fill, 1}]]},
    {"Min", [[{:percentage, 100}, {:min, 0}], [{:percentage, 100}, {:min, 30}], [{:percentage, 100}, {:min, 60}]]},
    {"Max", [[{:percentage, 0}, {:max, 0}], [{:percentage, 0}, {:max, 30}], [{:percentage, 0}, {:max, 60}]]}
  ]

  @impl true
  def init(_opts), do: %{tab: 0}

  @impl true
  def update(model, event) do
    cond do
      Examples.Support.quit?(event) -> :quit
      Examples.Support.key?(event, [:right, {:char, "l"}]) -> {:ok, %{model | tab: Examples.Support.cycle(model.tab, 1, length(@tabs))}}
      Examples.Support.key?(event, [:left, {:char, "h"}]) -> {:ok, %{model | tab: Examples.Support.cycle(model.tab, -1, length(@tabs))}}
      true -> {:ok, model}
    end
  end

  @impl true
  def view(model, frame) do
    [tabs_area, body, footer] =
      Layout.vertical([{:length, 3}, {:fill, 1}, {:length, 1}])
      |> Layout.split(Frame.area(frame))

    frame =
      Frame.render_widget(
        frame,
        Tabs.new(Enum.map(@tabs, &elem(&1, 0)),
          selected: model.tab,
          block: Block.bordered(title: "Constraints"),
          highlight_style: [fg: :yellow, add_modifier: [:bold]]
        ),
        tabs_area
      )

    {_title, examples} = Enum.at(@tabs, model.tab)

    rows =
      Layout.vertical(List.duplicate({:fill, 1}, length(examples)), spacing: 1)
      |> Layout.split(body)

    frame =
      Enum.zip(rows, examples)
      |> Enum.reduce(frame, fn {row, constraints}, acc -> render_example(acc, row, constraints) end)

    Examples.Support.render_footer(frame, footer, "h/l switch tabs, q quit")
  end

  defp render_example(frame, area, constraints) do
    [label_area, preview_area] =
      Layout.horizontal([{:length, 32}, {:fill, 1}], spacing: 1)
      |> Layout.split(area)

    frame =
      Frame.render_widget(
        frame,
        Paragraph.new(Enum.map_join(constraints, " + ", &label/1),
          wrap: [trim: true],
          block: Block.bordered(title: "Input")
        ),
        label_area
      )

    constraints
    |> Layout.horizontal(spacing: 1)
    |> Layout.split(preview_area)
    |> Enum.with_index()
    |> Enum.reduce(frame, fn {rect, i}, acc ->
      Frame.render_widget(
        acc,
        Paragraph.new(Line.new("#{rect.width} cells", alignment: :center),
          block: Block.bordered(title: label(Enum.at(constraints, i)), border_style: [fg: palette(i)])
        ),
        rect
      )
    end)
  end

  defp label({:ratio, n, d}), do: "Ratio(#{n}, #{d})"
  defp label({kind, value}), do: "#{Macro.camelize(to_string(kind))}(#{value})"

  defp palette(i), do: Enum.at([:cyan, :magenta, :green, :yellow, :light_blue, :light_red], rem(i, 6))
end

Examples.Support.run(Examples.Constraints)

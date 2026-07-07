Code.require_file("support/ratatui_port.exs", __DIR__)

# Advanced widget implementation demo: renders custom widgets directly,
# through helper functions, and from a container.
#
# Run with:
#
#     mix run examples/advanced_widget_impl.exs

defmodule Examples.AdvancedWidgetImpl do
  @behaviour Elui.App

  alias Elui.{Frame, Layout}
  alias Elui.Examples.Widgets.MetricTile
  alias Elui.Widgets.{Block, Gauge, Paragraph}

  @impl true
  def init(_opts), do: %{tick: 0}

  @impl true
  def update(model, event) do
    cond do
      Examples.Support.quit?(event) -> :quit
      event == :tick -> {:ok, %{model | tick: model.tick + 1}}
      true -> {:ok, model}
    end
  end

  @impl true
  def view(model, frame) do
    [header, body, footer] =
      Layout.vertical([{:length, 2}, {:fill, 1}, {:length, 1}])
      |> Layout.split(Frame.area(frame))

    ratios = ratios(model.tick)

    frame =
      Examples.Support.render_header(
        frame,
        header,
        "Advanced Widget Implementation",
        "custom structs implement Elui.Widget"
      )

    [left, middle, right] =
      Layout.horizontal([{:percentage, 34}, {:percentage, 33}, {:fill, 1}], spacing: 1)
      |> Layout.split(body)

    frame =
      Frame.render_widget(
        frame,
        MetricTile.new("direct render", "#{round(ratios.cpu * 100)}%", ratios.cpu, color: :cyan),
        left
      )

    frame =
      render_metric_with_block(
        frame,
        middle,
        "helper-rendered widget",
        MetricTile.new("memory", "#{round(ratios.mem * 100)}%", ratios.mem, color: :magenta)
      )

    widgets = [
      MetricTile.new("network", "#{round(ratios.net * 100)}%", ratios.net, color: :green),
      Gauge.new(ratios.cpu, block: Block.bordered(title: "nested Gauge"), gauge_style: [fg: :yellow])
    ]

    frame = render_widget_stack(frame, right, widgets)
    Examples.Support.render_footer(frame, footer, "q/Esc quit")
  end

  defp render_metric_with_block(frame, area, title, widget) do
    [label, content] =
      Layout.vertical([{:length, 3}, {:fill, 1}])
      |> Layout.split(area)

    frame
    |> Frame.render_widget(Paragraph.new(title, block: Block.bordered(title: "method")), label)
    |> Frame.render_widget(widget, content)
  end

  defp render_widget_stack(frame, area, widgets) do
    areas =
      Layout.vertical(List.duplicate({:fill, 1}, length(widgets)), spacing: 1)
      |> Layout.split(area)

    Enum.zip(areas, widgets)
    |> Enum.reduce(frame, fn {rect, widget}, acc -> Frame.render_widget(acc, widget, rect) end)
  end

  defp ratios(tick) do
    %{
      cpu: wave(tick, 0.0),
      mem: wave(tick, 1.7),
      net: wave(tick, 3.4)
    }
  end

  defp wave(tick, phase), do: (:math.sin(tick / 10 + phase) + 1) / 2
end

Examples.Support.run(Examples.AdvancedWidgetImpl, tick_rate: 100)

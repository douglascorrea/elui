Code.require_file("support/ratatui_port.exs", __DIR__)

# WidgetRef container demo: stores heterogeneous widgets and renders
# them from a single collection.
#
# Run with:
#
#     mix run examples/widget_ref_container.exs

defmodule Examples.WidgetRefContainer do
  @behaviour Elui.App

  alias Elui.{Frame, Layout}
  alias Elui.Examples.Widgets.MetricTile
  alias Elui.Widgets.{Block, Gauge, Paragraph, Sparkline}

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

    widgets = widgets(model.tick)

    areas =
      Layout.vertical(List.duplicate({:fill, 1}, length(widgets)), spacing: 1)
      |> Layout.split(body)

    frame =
      Examples.Support.render_header(frame, header, "WidgetRef Container", "heterogeneous widget list")

    frame =
      Enum.zip(areas, widgets)
      |> Enum.reduce(frame, fn {area, widget}, acc -> Frame.render_widget(acc, widget, area) end)

    Examples.Support.render_footer(frame, footer, "q/Esc quit")
  end

  defp widgets(tick) do
    ratio = (:math.sin(tick / 8) + 1) / 2

    [
      Paragraph.new("All entries in this list implement Elui.Widget.",
        alignment: :center,
        block: Block.bordered(title: "Paragraph")
      ),
      Gauge.new(ratio, block: Block.bordered(title: "Gauge"), gauge_style: [fg: :green]),
      Sparkline.new(Enum.map(0..40, fn i -> round((:math.sin((tick + i) / 5) + 1) * 20) end),
        block: Block.bordered(title: "Sparkline"),
        style: [fg: :yellow]
      ),
      MetricTile.new("Custom tile", "#{round(ratio * 100)}%", ratio, color: :magenta)
    ]
  end
end

Examples.Support.run(Examples.WidgetRefContainer, tick_rate: 100)

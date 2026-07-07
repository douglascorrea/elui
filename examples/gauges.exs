Code.require_file("support/ratatui_port.exs", __DIR__)

# Gauges example: Gauge, LineGauge, Sparkline and BarChart animating
# on the tick event.
#
# Run with:
#
#     mix run examples/gauges.exs
#
# Press `q` to quit.

defmodule Examples.Gauges do
  @behaviour Elui.App

  alias Elui.{Frame, Layout}
  alias Elui.Widgets.{BarChart, Block, Gauge, LineGauge, Sparkline}

  @impl true
  def init(_opts) do
    %{progress: 0.0, data: Enum.map(1..60, fn _ -> :rand.uniform(10) end)}
  end

  @impl true
  def update(_model, {:key, {:char, "q"}, _mods}), do: :quit

  def update(model, :tick) do
    progress = if model.progress >= 1.0, do: 0.0, else: model.progress + 0.02
    data = tl(model.data) ++ [:rand.uniform(10)]
    {:ok, %{model | progress: progress, data: data}}
  end

  def update(model, _event), do: {:ok, model}

  @impl true
  def view(model, frame) do
    [gauge_area, line_gauge_area, sparkline_area, barchart_area] =
      Layout.vertical([{:length, 3}, {:length, 3}, {:length, 5}, {:fill, 1}])
      |> Layout.split(Frame.area(frame))

    frame
    |> Frame.render_widget(
      Gauge.new(model.progress,
        block: Block.bordered(title: "Gauge"),
        gauge_style: [fg: :green]
      ),
      gauge_area
    )
    |> Frame.render_widget(
      LineGauge.new(model.progress,
        block: Block.bordered(title: "LineGauge"),
        filled_style: [fg: :blue],
        unfilled_style: [fg: :dark_gray]
      ),
      line_gauge_area
    )
    |> Frame.render_widget(
      Sparkline.new(model.data,
        block: Block.bordered(title: "Sparkline"),
        style: [fg: :yellow]
      ),
      sparkline_area
    )
    |> Frame.render_widget(
      BarChart.new(
        model.data |> Enum.take(10) |> Enum.with_index() |> Enum.map(fn {v, i} -> {"B#{i}", v} end),
        block: Block.bordered(title: "BarChart", title_bottom: "q to quit"),
        bar_width: 4,
        bar_style: [fg: :cyan],
        value_style: [fg: :black, bg: :cyan]
      ),
      barchart_area
    )
  end
end

Examples.Support.run(Examples.Gauges, tick_rate: 100)

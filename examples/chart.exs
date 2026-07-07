# Chart example: line and scatter datasets over animated data.
#
# Run with:
#
#     mix run examples/chart.exs
#
# Press `q` to quit.

defmodule Examples.Chart do
  @behaviour Elui.App

  alias Elui.Frame
  alias Elui.Widgets.Block
  alias Elui.Widgets.Chart
  alias Elui.Widgets.Chart.{Axis, Dataset}

  @impl true
  def init(_opts), do: %{phase: 0.0}

  @impl true
  def update(_model, {:key, {:char, "q"}, _mods}), do: :quit
  def update(model, :tick), do: {:ok, %{model | phase: model.phase + 0.2}}
  def update(model, _event), do: {:ok, model}

  @impl true
  def view(model, frame) do
    sin_data =
      for i <- 0..200 do
        x = i / 10
        {x, :math.sin(x + model.phase)}
      end

    cos_data =
      for i <- 0..40 do
        x = i / 2
        {x, :math.cos(x + model.phase)}
      end

    chart =
      Chart.new(
        [
          Dataset.new(sin_data, name: "sin(x)", graph_type: :line, style: [fg: :cyan]),
          Dataset.new(cos_data, name: "cos(x)", graph_type: :scatter, style: [fg: :yellow])
        ],
        x_axis: Axis.new(title: "X", bounds: {0.0, 20.0}, labels: ["0", "10", "20"]),
        y_axis: Axis.new(title: "Y", bounds: {-1.5, 1.5}, labels: ["-1.5", "0", "1.5"]),
        block: Block.bordered(title: "Chart", title_bottom: "q to quit")
      )

    Frame.render_widget(frame, chart, Frame.area(frame))
  end
end

Elui.App.run(Examples.Chart, tick_rate: 100)

Code.require_file("support/ratatui_port.exs", __DIR__)

# Gauge demo: animated gauges and related progress widgets.
#
# Run with:
#
#     mix run examples/gauge.exs

defmodule Examples.Gauge do
  @behaviour Elui.App

  alias Elui.{Frame, Layout}
  alias Elui.Widgets.{BarChart, Block, Gauge, LineGauge}

  @impl true
  def init(_opts), do: %{ratio: 0.0, running: false, tick: 0}

  @impl true
  def update(model, event) do
    cond do
      Examples.Support.quit?(event) ->
        :quit

      Examples.Support.key?(event, [:enter, :space]) ->
        {:ok, %{model | running: !model.running}}

      event == :tick and model.running ->
        {:ok, %{model | ratio: rem(round((model.ratio + 0.01) * 100), 101) / 100, tick: model.tick + 1}}

      true ->
        {:ok, model}
    end
  end

  @impl true
  def view(model, frame) do
    [header, body, footer] =
      Layout.vertical([{:length, 2}, {:fill, 1}, {:length, 1}])
      |> Layout.split(Frame.area(frame))

    frame =
      Examples.Support.render_header(
        frame,
        header,
        "Gauge",
        "Space/Enter start-pause, q quit"
      )

    [a, b, c, d] =
      Layout.vertical([{:length, 4}, {:length, 4}, {:length, 4}, {:fill, 1}], spacing: 1)
      |> Layout.split(body)

    bars =
      0..7
      |> Enum.map(fn i ->
        value = round((:math.sin(model.tick / 4 + i) + 1) * 30 + 10)
        {"B#{i}", value}
      end)

    frame
    |> Frame.render_widget(
      Gauge.new(model.ratio,
        block: Block.bordered(title: "Unicode gauge"),
        gauge_style: [fg: :green],
        label: "#{round(model.ratio * 100)}%"
      ),
      a
    )
    |> Frame.render_widget(
      Gauge.new(model.ratio,
        block: Block.bordered(title: "ASCII-ish gauge"),
        gauge_style: [fg: :yellow],
        use_unicode: false
      ),
      b
    )
    |> Frame.render_widget(
      LineGauge.new(1.0 - model.ratio,
        block: Block.bordered(title: "Line gauge"),
        filled_style: [fg: :magenta]
      ),
      c
    )
    |> Frame.render_widget(
      BarChart.new(bars,
        block: Block.bordered(title: "Progress history"),
        bar_width: 3,
        bar_style: [fg: :cyan],
        value_style: [fg: :black, bg: :cyan]
      ),
      d
    )
    |> Examples.Support.render_footer(footer, if(model.running, do: "running", else: "paused"))
  end
end

Examples.Support.run(Examples.Gauge, tick_rate: 80)

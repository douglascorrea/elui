Code.require_file("support/ratatui_port.exs", __DIR__)

# Weather demo: renders fixed forecast data with bar charts.
#
# Run with:
#
#     mix run examples/weather.exs

defmodule Examples.Weather do
  @behaviour Elui.App

  alias Elui.{Frame, Layout}
  alias Elui.Text.{Line, Span}
  alias Elui.Widgets.{BarChart, Block, Paragraph}

  @forecast [
    {"Mon", 22, 8, :cyan},
    {"Tue", 24, 12, :light_blue},
    {"Wed", 27, 3, :yellow},
    {"Thu", 23, 18, :blue},
    {"Fri", 25, 10, :light_cyan},
    {"Sat", 29, 0, :light_yellow},
    {"Sun", 28, 2, :green}
  ]

  @impl true
  def init(_opts), do: %{}

  @impl true
  def update(model, event) do
    if Examples.Support.quit?(event), do: :quit, else: {:ok, model}
  end

  @impl true
  def view(_model, frame) do
    [header, body, footer] =
      Layout.vertical([{:length, 2}, {:fill, 1}, {:length, 1}])
      |> Layout.split(Frame.area(frame))

    [left, right] =
      Layout.horizontal([{:percentage, 55}, {:fill, 1}], spacing: 1)
      |> Layout.split(body)

    temps = Enum.map(@forecast, fn {day, temp, _rain, _color} -> {day, temp} end)
    rain = Enum.map(@forecast, fn {day, _temp, rain, _color} -> {day, rain} end)

    summary =
      @forecast
      |> Enum.map(fn {day, temp, rain, color} ->
        Line.new([
          Span.new(String.pad_trailing(day, 4), fg: color, add_modifier: [:bold]),
          Span.new("#{temp}C  "),
          Span.new("#{rain}mm rain", fg: if(rain > 10, do: :blue, else: :dark_gray))
        ])
      end)

    frame =
      Examples.Support.render_header(frame, header, "Weather", "forecast rendered with BarChart")

    frame =
      Frame.render_widget(
        frame,
        BarChart.new(temps,
          block: Block.bordered(title: "Temperature C"),
          bar_width: 4,
          bar_style: [fg: :yellow],
          value_style: [fg: :black, bg: :yellow]
        ),
        left
      )

    [summary_area, rain_area] =
      Layout.vertical([{:fill, 1}, {:fill, 1}], spacing: 1)
      |> Layout.split(right)

    frame =
      Frame.render_widget(frame, Paragraph.new(summary, block: Block.bordered(title: "Summary")), summary_area)

    frame =
      Frame.render_widget(
        frame,
        BarChart.new(rain,
          block: Block.bordered(title: "Rain mm"),
          bar_width: 4,
          bar_style: [fg: :blue]
        ),
        rain_area
      )

    Examples.Support.render_footer(frame, footer, "q/Esc quit")
  end
end

Examples.Support.run(Examples.Weather)

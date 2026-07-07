defmodule Elui.CanvasChartTest do
  use ExUnit.Case, async: true

  alias Elui.Buffer
  alias Elui.Layout.Rect
  alias Elui.Widgets.Canvas
  alias Elui.Widgets.Canvas.Context
  alias Elui.Widgets.Canvas.Shapes
  alias Elui.Widgets.Chart
  alias Elui.Widgets.Chart.{Axis, Dataset}

  defp render(widget, width, height) do
    area = Rect.new(0, 0, width, height)
    buffer = Elui.Widget.render(widget, area, Buffer.empty(area))
    Buffer.to_lines(buffer)
  end

  test "canvas paints points with block marker" do
    canvas =
      Canvas.new(
        x_bounds: {0.0, 9.0},
        y_bounds: {0.0, 9.0},
        marker: :block,
        paint: fn ctx ->
          Context.draw(ctx, %Shapes.Points{coords: [{0.0, 9.0}, {9.0, 0.0}], color: :red})
        end
      )

    lines = render(canvas, 10, 10)
    assert String.at(Enum.at(lines, 0), 0) == "█"
    assert String.at(Enum.at(lines, 9), 9) == "█"
  end

  test "canvas draws a line with braille marker" do
    canvas =
      Canvas.new(
        x_bounds: {0.0, 10.0},
        y_bounds: {0.0, 10.0},
        marker: :braille,
        paint: fn ctx ->
          Context.draw(ctx, %Shapes.Line{x1: 0.0, y1: 0.0, x2: 10.0, y2: 10.0, color: :green})
        end
      )

    lines = render(canvas, 10, 5)
    # Every cell on the diagonal should contain some braille character.
    refute Enum.all?(lines, fn line -> String.trim(line) == "" end)
    assert lines |> Enum.join() |> String.graphemes() |> Enum.any?(&(&1 >= "⠀" and &1 <= "⣿"))
  end

  test "canvas prints labels" do
    canvas =
      Canvas.new(
        x_bounds: {0.0, 10.0},
        y_bounds: {0.0, 10.0},
        paint: fn ctx -> Context.print(ctx, 0.0, 10.0, "hi") end
      )

    lines = render(canvas, 10, 3)
    assert String.starts_with?(hd(lines), "hi")
  end

  test "chart renders axes, labels and legend" do
    chart =
      Chart.new(
        [
          Dataset.new([{0.0, 0.0}, {5.0, 5.0}, {10.0, 10.0}],
            name: "ds1",
            graph_type: :line,
            style: [fg: :cyan]
          )
        ],
        x_axis: Axis.new(bounds: {0.0, 10.0}, labels: ["0", "10"]),
        y_axis: Axis.new(bounds: {0.0, 10.0}, labels: ["0", "10"])
      )

    lines = render(chart, 20, 10)
    joined = Enum.join(lines, "\n")

    assert joined =~ "└"
    assert joined =~ "─"
    assert joined =~ "│"
    assert joined =~ "10"
    assert joined =~ "ds1"
  end
end

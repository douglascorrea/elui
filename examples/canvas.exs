Code.require_file("support/ratatui_port.exs", __DIR__)

# Canvas example: world-outline polylines, primitive shapes and a ball
# bouncing around the area.
#
# Run with:
#
#     mix run examples/canvas.exs
#
# Press `q` to quit.

defmodule Examples.Canvas do
  @behaviour Elui.App

  alias Elui.Frame
  alias Elui.Widgets.Block
  alias Elui.Widgets.Canvas
  alias Elui.Widgets.Canvas.Context
  alias Elui.Widgets.Canvas.Shapes

  @impl true
  def init(_opts) do
    %{x: 20.0, y: 20.0, dx: 1.5, dy: 1.0}
  end

  @impl true
  def update(_model, {:key, {:char, "q"}, _mods}), do: :quit

  def update(model, :tick) do
    x = model.x + model.dx
    y = model.y + model.dy
    dx = if x < 10 or x > 90, do: -model.dx, else: model.dx
    dy = if y < 10 or y > 90, do: -model.dy, else: model.dy
    {:ok, %{model | x: x, y: y, dx: dx, dy: dy}}
  end

  def update(model, _event), do: {:ok, model}

  @impl true
  def view(model, frame) do
    canvas =
      Canvas.new(
        x_bounds: {0.0, 100.0},
        y_bounds: {0.0, 100.0},
        marker: :braille,
        block: Block.bordered(title: "Canvas", title_bottom: "q to quit"),
        paint: fn ctx ->
          ctx
          |> draw_world()
          |> Context.draw(%Shapes.Rectangle{x: 5.0, y: 5.0, width: 90.0, height: 90.0, color: :green})
          |> Context.draw(%Shapes.Line{x1: 5.0, y1: 5.0, x2: 95.0, y2: 95.0, color: :dark_gray})
          |> Context.draw(%Shapes.Line{x1: 5.0, y1: 95.0, x2: 95.0, y2: 5.0, color: :dark_gray})
          |> Context.draw(%Shapes.Circle{x: model.x, y: model.y, radius: 5.0, color: :yellow})
          |> Context.print(8.0, 92.0, "bouncing ball")
        end
      )

    Frame.render_widget(frame, canvas, Frame.area(frame))
  end

  defp draw_world(ctx) do
    [
      [{12, 66}, {18, 78}, {28, 76}, {33, 64}, {28, 48}, {22, 38}, {24, 20}, {31, 11}],
      [{42, 69}, {54, 76}, {70, 70}, {82, 60}, {77, 47}, {63, 48}, {55, 38}, {47, 45}],
      [{52, 42}, {60, 34}, {62, 22}, {55, 12}, {48, 25}, {46, 36}, {52, 42}],
      [{74, 30}, {82, 33}, {89, 25}, {85, 16}, {75, 18}, {72, 25}, {74, 30}]
    ]
    |> Enum.reduce(ctx, fn points, acc -> draw_polyline(acc, points, :cyan) end)
  end

  defp draw_polyline(ctx, points, color) do
    points
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(ctx, fn [{x1, y1}, {x2, y2}], acc ->
      Context.draw(acc, %Shapes.Line{x1: x1, y1: y1, x2: x2, y2: y2, color: color})
    end)
  end
end

Examples.Support.run(Examples.Canvas, tick_rate: 50)

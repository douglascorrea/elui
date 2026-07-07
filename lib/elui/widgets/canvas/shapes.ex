defmodule Elui.Widgets.Canvas.Shapes do
  @moduledoc """
  Built-in shapes for `Elui.Widgets.Canvas`: `Line`, `Rectangle`,
  `Circle` and `Points`. Mirror ratatui's canvas shapes.
  """

  defmodule Line do
    @moduledoc "A straight line between two world-coordinate points."

    defstruct x1: 0.0, y1: 0.0, x2: 0.0, y2: 0.0, color: :reset

    @type t :: %__MODULE__{}

    defimpl Elui.Widgets.Canvas.Shape do
      alias Elui.Widgets.Canvas.Context

      def draw(line, ctx) do
        # Sample the segment densely enough to hit every grid cell.
        steps =
          max(
            ctx.grid_width * abs(line.x2 - line.x1) / span(ctx.x_bounds),
            ctx.grid_height * abs(line.y2 - line.y1) / span(ctx.y_bounds)
          )
          |> Kernel.*(2)
          |> ceil()
          |> max(1)

        Enum.reduce(0..steps, ctx, fn i, acc ->
          t = i / steps
          x = line.x1 + (line.x2 - line.x1) * t
          y = line.y1 + (line.y2 - line.y1) * t
          Context.point(acc, x, y, line.color)
        end)
      end

      defp span({min, max}) when max != min, do: max - min
      defp span(_), do: 1.0
    end
  end

  defmodule Rectangle do
    @moduledoc "An axis-aligned rectangle outline."

    defstruct x: 0.0, y: 0.0, width: 0.0, height: 0.0, color: :reset

    @type t :: %__MODULE__{}

    defimpl Elui.Widgets.Canvas.Shape do
      alias Elui.Widgets.Canvas.Context
      alias Elui.Widgets.Canvas.Shapes.Line

      def draw(rect, ctx) do
        c = rect.color

        ctx
        |> Context.draw(%Line{
          x1: rect.x,
          y1: rect.y,
          x2: rect.x + rect.width,
          y2: rect.y,
          color: c
        })
        |> Context.draw(%Line{
          x1: rect.x + rect.width,
          y1: rect.y,
          x2: rect.x + rect.width,
          y2: rect.y + rect.height,
          color: c
        })
        |> Context.draw(%Line{
          x1: rect.x + rect.width,
          y1: rect.y + rect.height,
          x2: rect.x,
          y2: rect.y + rect.height,
          color: c
        })
        |> Context.draw(%Line{
          x1: rect.x,
          y1: rect.y + rect.height,
          x2: rect.x,
          y2: rect.y,
          color: c
        })
      end
    end
  end

  defmodule Circle do
    @moduledoc "A circle outline centered at `{x, y}`."

    defstruct x: 0.0, y: 0.0, radius: 0.0, color: :reset

    @type t :: %__MODULE__{}

    defimpl Elui.Widgets.Canvas.Shape do
      alias Elui.Widgets.Canvas.Context

      def draw(circle, ctx) do
        steps = max(ctx.grid_width + ctx.grid_height, 16) * 2

        Enum.reduce(0..steps, ctx, fn i, acc ->
          angle = i / steps * 2 * :math.pi()
          x = circle.x + circle.radius * :math.cos(angle)
          y = circle.y + circle.radius * :math.sin(angle)
          Context.point(acc, x, y, circle.color)
        end)
      end
    end
  end

  defmodule Points do
    @moduledoc "A cloud of `{x, y}` points sharing one color."

    defstruct coords: [], color: :reset

    @type t :: %__MODULE__{}

    defimpl Elui.Widgets.Canvas.Shape do
      alias Elui.Widgets.Canvas.Context

      def draw(points, ctx) do
        Enum.reduce(points.coords, ctx, fn {x, y}, acc ->
          Context.point(acc, x, y, points.color)
        end)
      end
    end
  end
end

Code.require_file("support/ratatui_port.exs", __DIR__)

# Mouse drawing demo: draw points on a canvas with mouse drag, or with
# the keyboard cursor and Space.
#
# Run with:
#
#     mix run examples/mouse_drawing.exs

defmodule Examples.MouseDrawing do
  @behaviour Elui.App

  alias Elui.{Frame, Layout}
  alias Elui.Widgets.Canvas
  alias Elui.Widgets.Canvas.Context
  alias Elui.Widgets.Canvas.Shapes

  @colors [:cyan, :yellow, :green, :magenta, :light_red, :light_blue]

  @impl true
  def init(_opts) do
    %{points: [], cursor: {50.0, 50.0}, color: 0, size: {80, 24}}
  end

  @impl true
  def update(model, event) do
    cond do
      Examples.Support.quit?(event) ->
        :quit

      Examples.Support.key?(event, {:char, "c"}) ->
        {:ok, %{model | points: []}}

      Examples.Support.key?(event, [:left, {:char, "h"}]) ->
        {:ok, move_cursor(model, -2, 0)}

      Examples.Support.key?(event, [:right, {:char, "l"}]) ->
        {:ok, move_cursor(model, 2, 0)}

      Examples.Support.key?(event, [:up, {:char, "k"}]) ->
        {:ok, move_cursor(model, 0, 2)}

      Examples.Support.key?(event, [:down, {:char, "j"}]) ->
        {:ok, move_cursor(model, 0, -2)}

      Examples.Support.key?(event, :space) ->
        {:ok, add_point(model, model.cursor)}

      match?({:resize, _, _}, event) ->
        {:resize, width, height} = event
        {:ok, %{model | size: {width, height}}}

      match?({:mouse, _, _, _, _}, event) ->
        handle_mouse(model, event)

      true ->
        {:ok, model}
    end
  end

  @impl true
  def view(model, frame) do
    [header, canvas_area, footer] =
      Layout.vertical([{:length, 2}, {:fill, 1}, {:length, 1}])
      |> Layout.split(Frame.area(frame))

    color = Enum.at(@colors, model.color)

    frame =
      Examples.Support.render_header(
        frame,
        header,
        "Mouse Drawing",
        "drag/click to draw, scroll changes color, c clears"
      )

    frame =
      Frame.render_widget(
        frame,
        Canvas.new(
          x_bounds: {0.0, 100.0},
          y_bounds: {0.0, 100.0},
          block: Elui.Widgets.Block.bordered(title: "Canvas", border_style: [fg: color]),
          paint: fn ctx ->
            grouped =
              model.points
              |> Enum.group_by(&elem(&1, 2), fn {x, y, _color} -> {x, y} end)

            ctx =
              Enum.reduce(grouped, ctx, fn {point_color, coords}, acc ->
                Context.draw(acc, %Shapes.Points{coords: coords, color: point_color})
              end)

            {cx, cy} = model.cursor
            Context.draw(ctx, %Shapes.Circle{x: cx, y: cy, radius: 2.0, color: color})
          end
        ),
        canvas_area
      )

    Examples.Support.render_footer(frame, footer, "current color: #{color} · q/Esc quit")
  end

  defp handle_mouse(model, {:mouse, :scroll_up, _x, _y, _mods}) do
    {:ok, %{model | color: Examples.Support.cycle(model.color, 1, length(@colors))}}
  end

  defp handle_mouse(model, {:mouse, :scroll_down, _x, _y, _mods}) do
    {:ok, %{model | color: Examples.Support.cycle(model.color, -1, length(@colors))}}
  end

  defp handle_mouse(model, {:mouse, kind, x, y, _mods}) when kind in [{:down, :left}, {:drag, :left}] do
    point = to_world(model.size, x, y)
    {:ok, %{add_point(model, point) | cursor: point}}
  end

  defp handle_mouse(model, _event), do: {:ok, model}

  defp move_cursor(%{cursor: {x, y}} = model, dx, dy) do
    point = {Examples.Support.clamp(x + dx, 0.0, 100.0), Examples.Support.clamp(y + dy, 0.0, 100.0)}
    %{model | cursor: point}
  end

  defp add_point(model, {x, y}) do
    color = Enum.at(@colors, model.color)
    %{model | points: [{x, y, color} | model.points]}
  end

  defp to_world({width, height}, x, y) do
    x = Examples.Support.clamp(x / max(width - 1, 1) * 100, 0.0, 100.0)
    y = Examples.Support.clamp(100 - y / max(height - 1, 1) * 100, 0.0, 100.0)
    {x, y}
  end
end

Examples.Support.run(Examples.MouseDrawing, mouse: true, tick_rate: 80)

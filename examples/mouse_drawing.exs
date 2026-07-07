Code.require_file("support/ratatui_port.exs", __DIR__)

# Mouse drawing demo: draw continuous full-block lines with mouse drag.
#
# Run with:
#
#     mix run examples/mouse_drawing.exs

defmodule Examples.MouseDrawing do
  @behaviour Elui.App

  alias Elui.Frame
  alias Elui.Examples.Widgets.MouseDrawingSurface

  @title "Mouse Example ('Esc' to quit. Click / drag to draw. 'Space' to change color)"

  @impl true
  def init(_opts) do
    %{
      points: [],
      mouse_position: nil,
      current_color: random_color()
    }
  end

  @impl true
  def update(model, event) do
    cond do
      Examples.Support.quit?(event) ->
        :quit

      Examples.Support.key?(event, {:char, "c"}) ->
        {:ok, %{model | points: []}}

      Examples.Support.key?(event, :space) ->
        {:ok, %{model | current_color: random_color()}}

      match?({:mouse, _, _, _, _}, event) ->
        handle_mouse(model, event)

      true ->
        {:ok, model}
    end
  end

  @impl true
  def view(model, frame) do
    Frame.render_widget(
      frame,
      MouseDrawingSurface.new(
        points: model.points,
        mouse_position: model.mouse_position,
        current_color: model.current_color,
        title: @title
      ),
      Frame.area(frame)
    )
  end

  defp handle_mouse(model, {:mouse, {:down, _button}, x, y, _mods}) do
    position = {x, y}
    {:ok, %{model | points: [{position, model.current_color} | model.points], mouse_position: position}}
  end

  defp handle_mouse(model, {:mouse, {:drag, _button}, x, y, _mods}) do
    position = {x, y}
    {:ok, %{model | points: draw_line(model, position), mouse_position: position}}
  end

  defp handle_mouse(model, {:mouse, _kind, x, y, _mods}) do
    {:ok, %{model | mouse_position: {x, y}}}
  end

  defp draw_line(%{points: []} = model, position) do
    [{position, model.current_color}]
  end

  defp draw_line(model, {x1, y1} = position) do
    {{x0, y0}, _color} = hd(model.points)

    bresenham({x0, y0}, {x1, y1})
    |> Enum.map(&{&1, model.current_color})
    |> Kernel.++(model.points)
    |> then(fn points ->
      if hd(points) == {position, model.current_color} do
        points
      else
        [{position, model.current_color} | points]
      end
    end)
  end

  defp bresenham({x0, y0}, {x1, y1}) do
    dx = abs(x1 - x0)
    sx = if x0 < x1, do: 1, else: -1
    dy = -abs(y1 - y0)
    sy = if y0 < y1, do: 1, else: -1
    do_bresenham(x0, y0, x1, y1, dx + dy, dx, dy, sx, sy, [])
  end

  defp do_bresenham(x, y, x, y, _err, _dx, _dy, _sx, _sy, acc), do: Enum.reverse([{x, y} | acc])

  defp do_bresenham(x, y, x1, y1, err, dx, dy, sx, sy, acc) do
    e2 = 2 * err
    {x, err} = if e2 >= dy, do: {x + sx, err + dy}, else: {x, err}
    {y, err} = if e2 <= dx, do: {y + sy, err + dx}, else: {y, err}
    do_bresenham(x, y, x1, y1, err, dx, dy, sx, sy, [{x, y} | acc])
  end

  defp random_color do
    {:rgb, :rand.uniform(256) - 1, :rand.uniform(256) - 1, :rand.uniform(256) - 1}
  end
end

Examples.Support.run(Examples.MouseDrawing, mouse: true)

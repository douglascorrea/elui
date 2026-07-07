Code.require_file("support/ratatui_port.exs", __DIR__)

# Volatility Surface demo: projects a 3D wireframe surface onto a
# Braille canvas.
#
# Run with:
#
#     mix run examples/volatility_surface.exs

defmodule Examples.VolatilitySurface do
  @behaviour Elui.App

  alias Elui.{Frame, Layout}
  alias Elui.Widgets.Canvas
  alias Elui.Widgets.Canvas.Context
  alias Elui.Widgets.Canvas.Shapes

  @impl true
  def init(_opts), do: %{yaw: -0.6, pitch: 0.55, zoom: 1.0, tick: 0}

  @impl true
  def update(model, event) do
    cond do
      Examples.Support.quit?(event) ->
        :quit

      Examples.Support.key?(event, [:left, {:char, "h"}]) ->
        {:ok, %{model | yaw: model.yaw - 0.08}}

      Examples.Support.key?(event, [:right, {:char, "l"}]) ->
        {:ok, %{model | yaw: model.yaw + 0.08}}

      Examples.Support.key?(event, [:up, {:char, "k"}]) ->
        {:ok, %{model | pitch: min(model.pitch + 0.06, 1.2)}}

      Examples.Support.key?(event, [:down, {:char, "j"}]) ->
        {:ok, %{model | pitch: max(model.pitch - 0.06, -0.2)}}

      Examples.Support.key?(event, [{:char, "+"}, {:char, "="}]) ->
        {:ok, %{model | zoom: min(model.zoom + 0.08, 1.8)}}

      Examples.Support.key?(event, {:char, "-"}) ->
        {:ok, %{model | zoom: max(model.zoom - 0.08, 0.5)}}

      event == :tick ->
        {:ok, %{model | tick: model.tick + 1}}

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
        "Volatility Surface",
        "h/l yaw, j/k pitch, +/- zoom"
      )

    frame =
      Frame.render_widget(
        frame,
        Canvas.new(
          x_bounds: {-1.35, 1.35},
          y_bounds: {-1.0, 1.0},
          block: Elui.Widgets.Block.bordered(title: "3D wireframe", border_style: [fg: :cyan]),
          paint: fn ctx -> render_surface(ctx, model) end
        ),
        body
      )

    Examples.Support.render_footer(
      frame,
      footer,
      "yaw=#{Float.round(model.yaw, 2)} pitch=#{Float.round(model.pitch, 2)} zoom=#{Float.round(model.zoom, 2)}"
    )
  end

  defp render_surface(ctx, model) do
    strikes = for i <- -8..8, do: i / 8
    terms = for i <- 0..12, do: i / 12

    strike_lines =
      Enum.flat_map(strikes, fn strike ->
        terms
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [a, b] -> {point(strike, a), point(strike, b)} end)
      end)

    term_lines =
      Enum.flat_map(terms, fn term ->
        strikes
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [a, b] -> {point(a, term), point(b, term)} end)
      end)

    (strike_lines ++ term_lines)
    |> Enum.reduce(ctx, fn {from, to}, acc ->
      {x1, y1, color} = project(from, model)
      {x2, y2, _color} = project(to, model)
      Context.draw(acc, %Shapes.Line{x1: x1, y1: y1, x2: x2, y2: y2, color: color})
    end)
  end

  defp point(strike, term) do
    vol =
      0.22 +
        0.14 * :math.exp(-:math.pow(strike * 1.8, 2)) +
        0.08 * term +
        0.04 * :math.sin(strike * 4 + term * 5)

    {strike, term * 2 - 1, vol * 3 - 1}
  end

  defp project({x, y, z}, model) do
    {x, y} = rotate_yaw(x, y, model.yaw + model.tick / 160)
    {y, z} = rotate_pitch(y, z, model.pitch)
    depth = 2.6 + y
    px = x * model.zoom / depth * 2.2
    py = z * model.zoom / depth * 1.4
    color = if z > 0.0, do: :yellow, else: :light_blue
    {px, py, color}
  end

  defp rotate_yaw(x, y, angle) do
    {x * :math.cos(angle) - y * :math.sin(angle), x * :math.sin(angle) + y * :math.cos(angle)}
  end

  defp rotate_pitch(y, z, angle) do
    {y * :math.cos(angle) - z * :math.sin(angle), y * :math.sin(angle) + z * :math.cos(angle)}
  end
end

Examples.Support.run(Examples.VolatilitySurface, tick_rate: 80)

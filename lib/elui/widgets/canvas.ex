defprotocol Elui.Widgets.Canvas.Shape do
  @moduledoc """
  Protocol implemented by shapes that can be drawn on a
  `Elui.Widgets.Canvas` (lines, rectangles, circles, point clouds...).
  """

  @doc "Draws the shape into the canvas context."
  @spec draw(t(), Elui.Widgets.Canvas.Context.t()) :: Elui.Widgets.Canvas.Context.t()
  def draw(shape, context)
end

defmodule Elui.Widgets.Canvas.Context do
  @moduledoc """
  Drawing context handed to the canvas paint function. Supports
  painting world-coordinate points and printing text labels.
  """

  alias Elui.Widgets.Canvas.Shape

  defstruct grid: %{},
            labels: [],
            x_bounds: {0.0, 1.0},
            y_bounds: {0.0, 1.0},
            grid_width: 0,
            grid_height: 0

  @type t :: %__MODULE__{}

  @doc "Draws any shape implementing `Elui.Widgets.Canvas.Shape`."
  @spec draw(t(), Shape.t()) :: t()
  def draw(%__MODULE__{} = ctx, shape), do: Shape.draw(shape, ctx)

  @doc "Paints a single point in world coordinates."
  @spec point(t(), number(), number(), Elui.Style.Color.t()) :: t()
  def point(%__MODULE__{} = ctx, x, y, color) do
    case to_grid(ctx, x, y) do
      nil -> ctx
      {gx, gy} -> %{ctx | grid: Map.put(ctx.grid, {gx, gy}, color)}
    end
  end

  @doc "Prints a text label at the given world coordinates."
  @spec print(t(), number(), number(), term()) :: t()
  def print(%__MODULE__{} = ctx, x, y, line) do
    %{ctx | labels: [{x, y, Elui.Text.Line.to_line(line)} | ctx.labels]}
  end

  @doc false
  @spec to_grid(t(), number(), number()) :: {integer(), integer()} | nil
  def to_grid(%__MODULE__{} = ctx, x, y) do
    {x_min, x_max} = ctx.x_bounds
    {y_min, y_max} = ctx.y_bounds

    if x < x_min or x > x_max or y < y_min or y > y_max or x_max == x_min or y_max == y_min do
      nil
    else
      gx = trunc((x - x_min) / (x_max - x_min) * (ctx.grid_width - 1))
      gy = trunc((y_max - y) / (y_max - y_min) * (ctx.grid_height - 1))
      {gx, gy}
    end
  end
end

defmodule Elui.Widgets.Canvas do
  @moduledoc """
  Draws arbitrary shapes (lines, rectangles, circles, points) and text
  in a floating-point coordinate system, rasterized with braille,
  block, half-block or dot markers. Mirrors ratatui's `Canvas`.

  ## Example

      Canvas.new(
        x_bounds: {-180.0, 180.0},
        y_bounds: {-90.0, 90.0},
        marker: :braille,
        block: Block.bordered(title: "World"),
        paint: fn ctx ->
          ctx
          |> Context.draw(%Shapes.Line{x1: 0.0, y1: 0.0, x2: 100.0, y2: 50.0, color: :red})
          |> Context.draw(%Shapes.Circle{x: 0.0, y: 0.0, radius: 30.0, color: :green})
          |> Context.print(0.0, 0.0, "origin")
        end
      )
  """

  alias Elui.Buffer
  alias Elui.Layout.Rect
  alias Elui.Style
  alias Elui.Symbols.Braille
  alias Elui.Widgets.Block
  alias Elui.Widgets.Canvas.Context

  defstruct x_bounds: {0.0, 1.0},
            y_bounds: {0.0, 1.0},
            marker: :braille,
            block: nil,
            background_color: nil,
            paint: nil

  @type t :: %__MODULE__{}

  @doc """
  Creates a canvas.

  Options: `:x_bounds`, `:y_bounds` (`{min, max}` tuples), `:marker`
  (`:braille`, `:dot`, `:block`, `:bar`, `:half_block` or
  `{:custom, char}`), `:block`, `:background_color`, and `:paint`
  (a function receiving and returning a `Context`).
  """
  @spec new(Keyword.t()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      x_bounds: Keyword.get(opts, :x_bounds, {0.0, 1.0}),
      y_bounds: Keyword.get(opts, :y_bounds, {0.0, 1.0}),
      marker: Keyword.get(opts, :marker, :braille),
      block: Keyword.get(opts, :block),
      background_color: Keyword.get(opts, :background_color),
      paint: Keyword.get(opts, :paint)
    }
  end

  @doc false
  def render_into(%__MODULE__{} = canvas, area, buffer) do
    {inner, buffer} = Block.render_with_block(canvas.block, area, buffer)

    if Rect.empty?(inner) do
      buffer
    else
      buffer =
        if canvas.background_color do
          Buffer.set_style(buffer, inner, Style.new(bg: canvas.background_color))
        else
          buffer
        end

      {rx, ry} = resolution(canvas.marker)

      ctx = %Context{
        x_bounds: canvas.x_bounds,
        y_bounds: canvas.y_bounds,
        grid_width: inner.width * rx,
        grid_height: inner.height * ry
      }

      ctx = if canvas.paint, do: canvas.paint.(ctx), else: ctx

      buffer = rasterize(canvas.marker, ctx, inner, buffer)

      # Labels are drawn on top of the painted grid.
      Enum.reduce(Enum.reverse(ctx.labels), buffer, fn {x, y, line}, buf ->
        case Context.to_grid(%{ctx | grid_width: inner.width, grid_height: inner.height}, x, y) do
          nil ->
            buf

          {cx, cy} ->
            {buf, _} = Buffer.set_line(buf, inner.x + cx, inner.y + cy, line, inner.width - cx)
            buf
        end
      end)
    end
  end

  defp resolution(:braille), do: {2, 4}
  defp resolution(:half_block), do: {1, 2}
  defp resolution(_), do: {1, 1}

  defp rasterize(:braille, ctx, inner, buffer) do
    ctx.grid
    |> Enum.group_by(fn {{gx, gy}, _color} -> {div(gx, 2), div(gy, 4)} end)
    |> Enum.reduce(buffer, fn {{cx, cy}, points}, buf ->
      mask =
        Enum.reduce(points, 0, fn {{gx, gy}, _}, acc ->
          Bitwise.bor(acc, Braille.dot(rem(gx, 2), rem(gy, 4)))
        end)

      {_pos, color} = List.last(points)
      cell = Elui.Buffer.Cell.new(Braille.char(mask), Style.new(fg: color))
      existing = Buffer.get(buf, inner.x + cx, inner.y + cy)
      cell = %{cell | style: Style.patch(existing.style, cell.style)}
      Buffer.put(buf, inner.x + cx, inner.y + cy, cell)
    end)
  end

  defp rasterize(:half_block, ctx, inner, buffer) do
    ctx.grid
    |> Enum.group_by(fn {{gx, gy}, _color} -> {gx, div(gy, 2)} end)
    |> Enum.reduce(buffer, fn {{cx, cy}, points}, buf ->
      upper = Enum.find_value(points, fn {{_, gy}, c} -> if rem(gy, 2) == 0, do: c end)
      lower = Enum.find_value(points, fn {{_, gy}, c} -> if rem(gy, 2) == 1, do: c end)

      {symbol, style} =
        case {upper, lower} do
          {nil, nil} -> {" ", Style.new()}
          {u, nil} -> {"▀", Style.new(fg: u)}
          {nil, l} -> {"▄", Style.new(fg: l)}
          {u, l} when u == l -> {"█", Style.new(fg: u)}
          {u, l} -> {"▀", Style.new(fg: u, bg: l)}
        end

      Buffer.put(buf, inner.x + cx, inner.y + cy, Elui.Buffer.Cell.new(symbol, style))
    end)
  end

  defp rasterize(marker, ctx, inner, buffer) do
    symbol = Elui.Symbols.marker_symbol(marker)

    Enum.reduce(ctx.grid, buffer, fn {{gx, gy}, color}, buf ->
      Buffer.put(
        buf,
        inner.x + gx,
        inner.y + gy,
        Elui.Buffer.Cell.new(symbol, Style.new(fg: color))
      )
    end)
  end

  defimpl Elui.Widget do
    def render(canvas, area, buffer), do: Elui.Widgets.Canvas.render_into(canvas, area, buffer)
  end
end

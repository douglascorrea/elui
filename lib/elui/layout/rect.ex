defmodule Elui.Layout.Rect do
  @moduledoc """
  A rectangular area on the terminal, defined by its top-left corner
  position (`x`, `y`) and its `width` and `height`.

  Equivalent to ratatui's `Rect`.
  """

  defstruct x: 0, y: 0, width: 0, height: 0

  @type t :: %__MODULE__{
          x: non_neg_integer(),
          y: non_neg_integer(),
          width: non_neg_integer(),
          height: non_neg_integer()
        }

  @doc "Creates a new rect."
  @spec new(integer(), integer(), integer(), integer()) :: t()
  def new(x, y, width, height) do
    %__MODULE__{x: x, y: y, width: max(width, 0), height: max(height, 0)}
  end

  @doc "The number of cells covered by the rect."
  @spec area(t()) :: non_neg_integer()
  def area(%__MODULE__{width: w, height: h}), do: w * h

  @doc "Returns true when the rect covers no cells."
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{width: w, height: h}), do: w == 0 or h == 0

  @spec left(t()) :: integer()
  def left(%__MODULE__{x: x}), do: x

  @spec right(t()) :: integer()
  def right(%__MODULE__{x: x, width: w}), do: x + w

  @spec top(t()) :: integer()
  def top(%__MODULE__{y: y}), do: y

  @spec bottom(t()) :: integer()
  def bottom(%__MODULE__{y: y, height: h}), do: y + h

  @doc """
  Returns a rect inside this one, deflated by the given margin.

  The margin may be an integer (applied on all sides), a
  `{horizontal, vertical}` tuple, or a keyword list with `:left`,
  `:right`, `:top` and `:bottom` keys.
  """
  @spec inner(t(), integer() | {integer(), integer()} | Keyword.t()) :: t()
  def inner(rect, margin)

  def inner(%__MODULE__{} = rect, m) when is_integer(m), do: inner(rect, {m, m})

  def inner(%__MODULE__{} = rect, {h, v}) do
    inner(rect, left: h, right: h, top: v, bottom: v)
  end

  def inner(%__MODULE__{} = rect, margin) when is_list(margin) do
    left = Keyword.get(margin, :left, 0)
    right = Keyword.get(margin, :right, 0)
    top = Keyword.get(margin, :top, 0)
    bottom = Keyword.get(margin, :bottom, 0)

    if rect.width <= left + right or rect.height <= top + bottom do
      %__MODULE__{x: rect.x, y: rect.y, width: 0, height: 0}
    else
      %__MODULE__{
        x: rect.x + left,
        y: rect.y + top,
        width: rect.width - left - right,
        height: rect.height - top - bottom
      }
    end
  end

  @doc "Moves the rect by the given `{dx, dy}` offset without changing its size."
  @spec offset(t(), {integer(), integer()}) :: t()
  def offset(%__MODULE__{} = rect, {dx, dy}) do
    %__MODULE__{rect | x: max(rect.x + dx, 0), y: max(rect.y + dy, 0)}
  end

  @doc "Returns the smallest rect containing both rects."
  @spec union(t(), t()) :: t()
  def union(%__MODULE__{} = a, %__MODULE__{} = b) do
    x1 = min(a.x, b.x)
    y1 = min(a.y, b.y)
    x2 = max(right(a), right(b))
    y2 = max(bottom(a), bottom(b))
    new(x1, y1, x2 - x1, y2 - y1)
  end

  @doc "Returns the overlapping area of both rects (possibly empty)."
  @spec intersection(t(), t()) :: t()
  def intersection(%__MODULE__{} = a, %__MODULE__{} = b) do
    x1 = max(a.x, b.x)
    y1 = max(a.y, b.y)
    x2 = min(right(a), right(b))
    y2 = min(bottom(a), bottom(b))
    new(x1, y1, max(x2 - x1, 0), max(y2 - y1, 0))
  end

  @doc "Returns true when the rects overlap."
  @spec intersects?(t(), t()) :: boolean()
  def intersects?(%__MODULE__{} = a, %__MODULE__{} = b) do
    a.x < right(b) and right(a) > b.x and a.y < bottom(b) and bottom(a) > b.y
  end

  @doc "Returns true when the `{x, y}` position lies inside the rect."
  @spec contains?(t(), {integer(), integer()}) :: boolean()
  def contains?(%__MODULE__{} = rect, {px, py}) do
    px >= rect.x and px < right(rect) and py >= rect.y and py < bottom(rect)
  end

  @doc "Clamps this rect so that it fits inside `other`, preserving size when possible."
  @spec clamp(t(), t()) :: t()
  def clamp(%__MODULE__{} = rect, %__MODULE__{} = other) do
    width = min(rect.width, other.width)
    height = min(rect.height, other.height)
    x = rect.x |> max(other.x) |> min(right(other) - width)
    y = rect.y |> max(other.y) |> min(bottom(other) - height)
    new(x, y, width, height)
  end

  @doc "Enumerates all `{x, y}` positions inside the rect (row by row)."
  @spec positions(t()) :: Enumerable.t()
  def positions(%__MODULE__{} = rect) do
    for y <- rect.y..(bottom(rect) - 1)//1, x <- rect.x..(right(rect) - 1)//1, do: {x, y}
  end

  @doc """
  Returns a rect of the given size centered inside this one, using
  layout constraints for width and height (like ratatui's
  `Rect::centered`). Useful for popups.

      Rect.centered(area, {:percentage, 50}, {:length, 3})
  """
  @spec centered(t(), Elui.Layout.Constraint.t(), Elui.Layout.Constraint.t()) :: t()
  def centered(%__MODULE__{} = rect, horizontal, vertical) do
    [h] =
      Elui.Layout.split(
        %Elui.Layout{direction: :horizontal, constraints: [horizontal], flex: :center},
        rect
      )

    [v] =
      Elui.Layout.split(
        %Elui.Layout{direction: :vertical, constraints: [vertical], flex: :center},
        h
      )

    v
  end

  @doc "Splits the rect into `n` equal rows."
  @spec rows(t(), pos_integer()) :: [t()]
  def rows(%__MODULE__{} = rect, n) do
    Elui.Layout.split(
      %Elui.Layout{direction: :vertical, constraints: List.duplicate({:ratio, 1, n}, n)},
      rect
    )
  end

  @doc "Splits the rect into `n` equal columns."
  @spec columns(t(), pos_integer()) :: [t()]
  def columns(%__MODULE__{} = rect, n) do
    Elui.Layout.split(
      %Elui.Layout{direction: :horizontal, constraints: List.duplicate({:ratio, 1, n}, n)},
      rect
    )
  end
end

defmodule Elui.Layout do
  @moduledoc """
  Splits a `Elui.Layout.Rect` area into multiple segments based on a
  direction and a list of constraints.

  Mirrors ratatui's `Layout`, including flex modes and spacing.

  ## Example

      alias Elui.Layout
      alias Elui.Layout.Rect

      area = Rect.new(0, 0, 80, 24)

      [top, body, bottom] =
        Layout.vertical([{:length, 3}, {:fill, 1}, {:length, 1}])
        |> Layout.split(area)

      [left, right] =
        Layout.horizontal([{:percentage, 30}, {:percentage, 70}])
        |> Layout.split(body)
  """

  alias Elui.Layout.Rect

  defstruct direction: :vertical,
            constraints: [],
            margin: {0, 0},
            spacing: 0,
            flex: :legacy

  @type direction :: :vertical | :horizontal
  @type flex :: :legacy | :start | :end | :center | :space_between | :space_around | :space_evenly

  @type t :: %__MODULE__{
          direction: direction(),
          constraints: [Elui.Layout.Constraint.t()],
          margin: {non_neg_integer(), non_neg_integer()},
          spacing: non_neg_integer(),
          flex: flex()
        }

  @doc """
  Creates a new layout.

  Options:

    * `:direction` - `:vertical` (default) or `:horizontal`
    * `:constraints` - list of constraints (see `Elui.Layout.Constraint`)
    * `:margin` - integer or `{horizontal, vertical}` tuple
    * `:spacing` - cells left between each segment
    * `:flex` - one of `:legacy`, `:start`, `:end`, `:center`,
      `:space_between`, `:space_around`, `:space_evenly`
  """
  @spec new(Keyword.t()) :: t()
  def new(opts \\ []) do
    margin =
      case Keyword.get(opts, :margin, {0, 0}) do
        m when is_integer(m) -> {m, m}
        {_h, _v} = m -> m
      end

    %__MODULE__{
      direction: Keyword.get(opts, :direction, :vertical),
      constraints: Keyword.get(opts, :constraints, []),
      margin: margin,
      spacing: Keyword.get(opts, :spacing, 0),
      flex: Keyword.get(opts, :flex, :legacy)
    }
  end

  @doc "Shorthand for a vertical layout with the given constraints."
  @spec vertical([Elui.Layout.Constraint.t()], Keyword.t()) :: t()
  def vertical(constraints, opts \\ []) do
    new(Keyword.merge(opts, direction: :vertical, constraints: constraints))
  end

  @doc "Shorthand for a horizontal layout with the given constraints."
  @spec horizontal([Elui.Layout.Constraint.t()], Keyword.t()) :: t()
  def horizontal(constraints, opts \\ []) do
    new(Keyword.merge(opts, direction: :horizontal, constraints: constraints))
  end

  @doc "Sets the flex mode."
  @spec flex(t(), flex()) :: t()
  def flex(%__MODULE__{} = layout, flex), do: %{layout | flex: flex}

  @doc "Sets the spacing between segments."
  @spec spacing(t(), non_neg_integer()) :: t()
  def spacing(%__MODULE__{} = layout, spacing), do: %{layout | spacing: spacing}

  @doc "Sets the margin around all segments."
  @spec margin(t(), non_neg_integer() | {non_neg_integer(), non_neg_integer()}) :: t()
  def margin(%__MODULE__{} = layout, m) when is_integer(m), do: %{layout | margin: {m, m}}
  def margin(%__MODULE__{} = layout, {_, _} = m), do: %{layout | margin: m}

  @doc """
  Splits `area` into a list of rects, one per constraint, in order.
  """
  @spec split(t(), Rect.t()) :: [Rect.t()]
  def split(%__MODULE__{constraints: []}, _area), do: []

  def split(%__MODULE__{} = layout, %Rect{} = area) do
    {mh, mv} = layout.margin
    inner = Rect.inner(area, {mh, mv})

    {total, cross_start, cross_size, main_start} =
      case layout.direction do
        :vertical -> {inner.height, inner.x, inner.width, inner.y}
        :horizontal -> {inner.width, inner.y, inner.height, inner.x}
      end

    n = length(layout.constraints)
    spacing_total = layout.spacing * max(n - 1, 0)
    available = max(total - spacing_total, 0)

    sizes = resolve_sizes(layout.constraints, available, layout.flex)
    leftover = max(available - Enum.sum(sizes), 0)
    {lead, gaps} = distribute_flex(layout.flex, leftover, n, layout.spacing)

    {rects, _pos} =
      sizes
      |> Enum.zip(gaps)
      |> Enum.reduce({[], main_start + lead}, fn {size, gap_after}, {acc, pos} ->
        rect =
          case layout.direction do
            :vertical -> Rect.new(cross_start, pos, cross_size, size)
            :horizontal -> Rect.new(pos, cross_start, size, cross_size)
          end

        {[rect | acc], pos + size + gap_after}
      end)

    Enum.reverse(rects)
  end

  @doc "Same as `split/2`; provided to mirror ratatui's `areas` naming."
  @spec areas(t(), Rect.t()) :: [Rect.t()]
  def areas(%__MODULE__{} = layout, %Rect{} = area), do: split(layout, area)

  # -- sizing ---------------------------------------------------------------

  defp resolve_sizes(constraints, available, flex) do
    base =
      Enum.map(constraints, fn
        {:length, n} -> n
        {:percentage, p} -> round(available * p / 100)
        {:ratio, num, den} -> round(available * num / den)
        {:min, n} -> n
        {:max, n} -> n
        {:fill, _} -> 0
      end)

    used = Enum.sum(base)

    cond do
      used > available ->
        shrink(constraints, base, used - available)

      used < available ->
        grow(constraints, base, available - used, flex)

      true ->
        base
    end
  end

  # Distribute excess space. Fill constraints always absorb it; otherwise in
  # legacy mode Min constraints grow, falling back to the last segment.
  defp grow(constraints, base, excess, flex) do
    fill_weights =
      Enum.map(constraints, fn
        {:fill, w} -> w
        _ -> 0
      end)

    cond do
      Enum.sum(fill_weights) > 0 ->
        add_proportionally(base, fill_weights, excess)

      flex == :legacy ->
        min_weights =
          Enum.map(constraints, fn
            {:min, _} -> 1
            _ -> 0
          end)

        if Enum.sum(min_weights) > 0 do
          add_proportionally(base, min_weights, excess)
        else
          List.update_at(base, -1, &(&1 + excess))
        end

      true ->
        # Non-legacy flex modes leave the excess as whitespace.
        base
    end
  end

  # Shrink segments proportionally to their size when they overflow,
  # never going below zero.
  defp shrink(_constraints, base, overflow) do
    total = Enum.sum(base)

    if total <= 0 do
      base
    else
      target = total - overflow

      scaled =
        Enum.map(base, fn size -> {size, size * target / total} end)

      floored = Enum.map(scaled, fn {_orig, exact} -> trunc(exact) end)
      shortfall = target - Enum.sum(floored)

      # Largest remainder method to hand out the rounding leftovers.
      order =
        scaled
        |> Enum.with_index()
        |> Enum.sort_by(fn {{_orig, exact}, _i} -> -(exact - trunc(exact)) end)
        |> Enum.map(fn {_pair, i} -> i end)
        |> Enum.take(shortfall)

      floored
      |> Enum.with_index()
      |> Enum.map(fn {size, i} -> if i in order, do: size + 1, else: size end)
    end
  end

  defp add_proportionally(base, weights, amount) do
    total_weight = Enum.sum(weights)

    exact = Enum.map(weights, fn w -> amount * w / total_weight end)
    floored = Enum.map(exact, &trunc/1)
    shortfall = amount - Enum.sum(floored)

    order =
      exact
      |> Enum.with_index()
      |> Enum.sort_by(fn {e, _i} -> -(e - trunc(e)) end)
      |> Enum.map(fn {_e, i} -> i end)
      |> Enum.take(shortfall)

    base
    |> Enum.zip(Enum.with_index(floored))
    |> Enum.map(fn {size, {extra, i}} ->
      size + extra + if i in order, do: 1, else: 0
    end)
  end

  # -- positioning ----------------------------------------------------------

  # Returns {leading_space, gaps_after_each_segment}
  defp distribute_flex(flex, leftover, n, spacing) do
    base_gaps = List.duplicate(spacing, max(n - 1, 0)) ++ [0]

    case flex do
      f when f in [:legacy, :start] ->
        {0, base_gaps}

      :end ->
        {leftover, base_gaps}

      :center ->
        {div(leftover, 2), base_gaps}

      :space_between ->
        if n <= 1 do
          {div(leftover, 2), base_gaps}
        else
          extra = split_evenly(leftover, n - 1)
          {0, Enum.zip_with(base_gaps, extra ++ [0], &+/2)}
        end

      :space_around ->
        slots = split_evenly(leftover, n + 1)
        {hd(slots), Enum.zip_with(base_gaps, tl(slots), &+/2)}

      :space_evenly ->
        slots = split_evenly(leftover, n + 1)
        {hd(slots), Enum.zip_with(base_gaps, tl(slots), &+/2)}
    end
  end

  defp split_evenly(_amount, slots) when slots <= 0, do: []

  defp split_evenly(amount, slots) do
    base = div(amount, slots)
    rem = rem(amount, slots)
    Enum.map(0..(slots - 1), fn i -> base + if i < rem, do: 1, else: 0 end)
  end
end

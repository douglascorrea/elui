defmodule Elui.Layout.Constraint do
  @moduledoc """
  Constraints used by `Elui.Layout` to define the size of layout segments.

  A constraint is a plain tagged tuple, mirroring ratatui's `Constraint`:

    * `{:length, n}` - exactly `n` cells
    * `{:percentage, p}` - `p`% of the available space
    * `{:ratio, num, den}` - `num/den` of the available space
    * `{:min, n}` - at least `n` cells (grows to absorb excess space)
    * `{:max, n}` - at most `n` cells
    * `{:fill, weight}` - fills remaining space proportionally to `weight`

  The functions in this module are convenience constructors.
  """

  @type t ::
          {:length, non_neg_integer()}
          | {:percentage, non_neg_integer()}
          | {:ratio, non_neg_integer(), pos_integer()}
          | {:min, non_neg_integer()}
          | {:max, non_neg_integer()}
          | {:fill, non_neg_integer()}

  @spec length(non_neg_integer()) :: t()
  def length(n) when is_integer(n) and n >= 0, do: {:length, n}

  @spec percentage(non_neg_integer()) :: t()
  def percentage(p) when is_integer(p) and p >= 0, do: {:percentage, p}

  @spec ratio(non_neg_integer(), pos_integer()) :: t()
  def ratio(num, den) when is_integer(num) and is_integer(den) and den > 0, do: {:ratio, num, den}

  @spec min(non_neg_integer()) :: t()
  def min(n) when is_integer(n) and n >= 0, do: {:min, n}

  @spec max(non_neg_integer()) :: t()
  def max(n) when is_integer(n) and n >= 0, do: {:max, n}

  @spec fill(non_neg_integer()) :: t()
  def fill(weight \\ 1) when is_integer(weight) and weight >= 0, do: {:fill, weight}

  @doc "Returns true for any valid constraint tuple."
  @spec constraint?(term()) :: boolean()
  def constraint?({:length, n}) when is_integer(n), do: true
  def constraint?({:percentage, n}) when is_integer(n), do: true
  def constraint?({:ratio, a, b}) when is_integer(a) and is_integer(b), do: true
  def constraint?({:min, n}) when is_integer(n), do: true
  def constraint?({:max, n}) when is_integer(n), do: true
  def constraint?({:fill, n}) when is_integer(n), do: true
  def constraint?(_), do: false

  @doc """
  Applies the constraint to a given length, returning the resulting size.
  Used for simple one-dimensional sizing (percentages, ratios, etc.).
  """
  @spec apply(t(), non_neg_integer()) :: non_neg_integer()
  def apply({:length, n}, total), do: Kernel.min(n, total)
  def apply({:percentage, p}, total), do: Kernel.min(div(total * p, 100), total)
  def apply({:ratio, num, den}, total), do: Kernel.min(div(total * num, den), total)
  def apply({:min, n}, total), do: Kernel.max(Kernel.min(n, total), Kernel.min(n, total))
  def apply({:max, n}, total), do: Kernel.min(n, total)
  def apply({:fill, _}, total), do: total
end

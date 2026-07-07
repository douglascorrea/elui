defmodule Elui.Widgets.Sparkline do
  @moduledoc """
  A compact bar chart drawn with eighth-block characters, one column
  per data point. Mirrors ratatui's `Sparkline`.

  ## Example

      Sparkline.new([0, 2, 3, 4, 1, 4, 10],
        block: Block.bordered(title: "Sparkline"),
        style: [fg: :yellow]
      )
  """

  alias Elui.Buffer
  alias Elui.Layout.Rect
  alias Elui.Style
  alias Elui.Widgets.Block

  defstruct data: [],
            block: nil,
            style: %Style{},
            max: nil,
            direction: :left_to_right,
            absent_value_symbol: " "

  @type t :: %__MODULE__{}

  @doc """
  Creates a sparkline from a list of non-negative numbers (`nil`
  entries render as absent values).

  Options: `:block`, `:style`, `:max` (scale ceiling; defaults to the
  data max), `:direction` (`:left_to_right` or `:right_to_left`),
  `:absent_value_symbol`.
  """
  @spec new([number() | nil], Keyword.t()) :: t()
  def new(data, opts \\ []) do
    %__MODULE__{
      data: data,
      block: Keyword.get(opts, :block),
      style: Style.to_style(Keyword.get(opts, :style)),
      max: Keyword.get(opts, :max),
      direction: Keyword.get(opts, :direction, :left_to_right),
      absent_value_symbol: Keyword.get(opts, :absent_value_symbol, " ")
    }
  end

  @doc false
  def render_into(%__MODULE__{} = sparkline, area, buffer) do
    buffer = Buffer.set_style(buffer, area, sparkline.style)
    {inner, buffer} = Block.render_with_block(sparkline.block, area, buffer)

    if Rect.empty?(inner) or sparkline.data == [] do
      buffer
    else
      data = Enum.take(sparkline.data, inner.width)
      max_value = sparkline.max || data |> Enum.reject(&is_nil/1) |> Enum.max(fn -> 1 end)
      max_value = max(max_value, 1)
      levels = Elui.Symbols.Bar.nine_levels()

      data
      |> Enum.with_index()
      |> Enum.reduce(buffer, fn {value, i}, buf ->
        x =
          case sparkline.direction do
            :left_to_right -> inner.x + i
            :right_to_left -> Rect.right(inner) - 1 - i
          end

        case value do
          nil ->
            Buffer.set_string(
              buf,
              x,
              Rect.bottom(inner) - 1,
              sparkline.absent_value_symbol,
              sparkline.style
            )

          value ->
            # Total height in eighth-block units for this column.
            total_eighths = round(value / max_value * inner.height * 8)

            Enum.reduce(0..(inner.height - 1)//1, buf, fn row, b ->
              y = Rect.bottom(inner) - 1 - row
              remaining = total_eighths - row * 8

              symbol =
                cond do
                  remaining >= 8 -> Enum.at(levels, 8)
                  remaining > 0 -> Enum.at(levels, remaining)
                  true -> nil
                end

              if symbol do
                Buffer.put(b, x, y, Elui.Buffer.Cell.new(symbol, sparkline.style))
              else
                b
              end
            end)
        end
      end)
    end
  end

  defimpl Elui.Widget do
    def render(sparkline, area, buffer) do
      Elui.Widgets.Sparkline.render_into(sparkline, area, buffer)
    end
  end
end

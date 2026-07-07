defmodule Elui.Widgets.LineGauge do
  @moduledoc """
  A compact, single-line progress bar. Mirrors ratatui's `LineGauge`.

  ## Example

      LineGauge.new(0.7,
        label: "DL",
        filled_style: [fg: :blue],
        unfilled_style: [fg: :dark_gray]
      )
  """

  alias Elui.Buffer
  alias Elui.Layout.Rect
  alias Elui.Style
  alias Elui.Text.Span
  alias Elui.Widgets.Block

  defstruct ratio: 0.0,
            block: nil,
            style: %Style{},
            filled_style: %Style{},
            unfilled_style: %Style{},
            label: nil,
            filled_symbol: "━",
            unfilled_symbol: "━"

  @type t :: %__MODULE__{}

  @doc """
  Creates a line gauge for `ratio` (0.0 to 1.0).

  Options: `:block`, `:style`, `:filled_style`, `:unfilled_style`,
  `:label`, `:filled_symbol`, `:unfilled_symbol`.
  """
  @spec new(number(), Keyword.t()) :: t()
  def new(ratio, opts \\ []) do
    %__MODULE__{
      ratio: min(max(ratio / 1, 0.0), 1.0),
      block: Keyword.get(opts, :block),
      style: Style.to_style(Keyword.get(opts, :style)),
      filled_style: Style.to_style(Keyword.get(opts, :filled_style)),
      unfilled_style: Style.to_style(Keyword.get(opts, :unfilled_style)),
      label: Keyword.get(opts, :label),
      filled_symbol: Keyword.get(opts, :filled_symbol, "━"),
      unfilled_symbol: Keyword.get(opts, :unfilled_symbol, "━")
    }
  end

  @doc false
  def render_into(%__MODULE__{} = gauge, area, buffer) do
    buffer = Buffer.set_style(buffer, area, gauge.style)
    {inner, buffer} = Block.render_with_block(gauge.block, area, buffer)

    if Rect.empty?(inner) do
      buffer
    else
      label =
        case gauge.label do
          nil -> Span.new("#{round(gauge.ratio * 100)}% ")
          %Span{} = span -> span
          other -> Span.new(to_string(other) <> " ")
        end

      {buffer, x} = Buffer.set_span(buffer, inner.x, inner.y, label, inner.width)

      bar_width = Rect.right(inner) - x
      filled = round(gauge.ratio * bar_width)

      buffer =
        Enum.reduce(0..(bar_width - 1)//1, buffer, fn i, buf ->
          {symbol, style} =
            if i < filled do
              {gauge.filled_symbol, gauge.filled_style}
            else
              {gauge.unfilled_symbol, gauge.unfilled_style}
            end

          Buffer.put(buf, x + i, inner.y, Elui.Buffer.Cell.new(symbol, style))
        end)

      buffer
    end
  end

  defimpl Elui.Widget do
    def render(gauge, area, buffer), do: Elui.Widgets.LineGauge.render_into(gauge, area, buffer)
  end
end

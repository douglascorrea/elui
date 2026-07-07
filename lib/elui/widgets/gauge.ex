defmodule Elui.Widgets.Gauge do
  @moduledoc """
  A progress bar filling an area proportionally to a ratio between 0
  and 1, with an optional label. Mirrors ratatui's `Gauge`.

  ## Example

      Gauge.new(0.42,
        block: Block.bordered(title: "Progress"),
        gauge_style: [fg: :green],
        label: "42%"
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
            gauge_style: %Style{},
            label: nil,
            use_unicode: true

  @type t :: %__MODULE__{}

  @doc """
  Creates a gauge for `ratio` (0.0 to 1.0). Also accepts an integer
  percent (0 to 100).

  Options: `:block`, `:style`, `:gauge_style`, `:label` (string or
  span, defaults to the percentage), `:use_unicode` (sub-cell
  resolution using eighth blocks).
  """
  @spec new(number(), Keyword.t()) :: t()
  def new(ratio, opts \\ []) do
    ratio =
      cond do
        is_integer(ratio) -> ratio / 100
        true -> ratio
      end

    %__MODULE__{
      ratio: min(max(ratio, 0.0), 1.0),
      block: Keyword.get(opts, :block),
      style: Style.to_style(Keyword.get(opts, :style)),
      gauge_style: Style.to_style(Keyword.get(opts, :gauge_style)),
      label: Keyword.get(opts, :label),
      use_unicode: Keyword.get(opts, :use_unicode, true)
    }
  end

  @doc false
  def render_into(%__MODULE__{} = gauge, area, buffer) do
    buffer = Buffer.set_style(buffer, area, gauge.style)
    {inner, buffer} = Block.render_with_block(gauge.block, area, buffer)

    if Rect.empty?(inner) do
      buffer
    else
      buffer = Buffer.set_style(buffer, inner, gauge.gauge_style)

      filled = gauge.ratio * inner.width
      full_cells = trunc(filled)
      remainder = filled - full_cells

      buffer =
        Enum.reduce(0..(inner.height - 1)//1, buffer, fn dy, buf ->
          y = inner.y + dy

          buf =
            Enum.reduce(0..(inner.width - 1)//1, buf, fn dx, b ->
              x = inner.x + dx

              cond do
                dx < full_cells ->
                  Buffer.set_symbol(b, x, y, "█")

                dx == full_cells and gauge.use_unicode and remainder > 0 ->
                  index = round(remainder * 8)
                  symbol = Enum.at(Elui.Symbols.Block.nine_levels(), index, " ")
                  Buffer.set_symbol(b, x, y, symbol)

                true ->
                  Buffer.set_symbol(b, x, y, " ")
              end
            end)

          buf
        end)

      label =
        case gauge.label do
          nil -> Span.new("#{round(gauge.ratio * 100)}%")
          %Span{} = span -> span
          other -> Span.new(to_string(other))
        end

      label_width = Span.width(label)
      label_x = inner.x + max(div(inner.width - label_width, 2), 0)
      label_y = inner.y + div(inner.height, 2)

      {buffer, _} = Buffer.set_span(buffer, label_x, label_y, label, inner.width)
      buffer
    end
  end

  defimpl Elui.Widget do
    def render(gauge, area, buffer), do: Elui.Widgets.Gauge.render_into(gauge, area, buffer)
  end
end

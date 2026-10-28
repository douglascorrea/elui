defmodule Elui.Widgets.Mermaid do
  @moduledoc """
  Draws a Mermaid diagram, a flowchart or a sequence diagram, in
  box-drawing characters (see `Elui.Mermaid`).

  ## Example

      Mermaid.new(\"""
      flowchart LR
        A[Request] --> B{Cached?}
        B -->|Yes| C[Reply]
        B -->|No| D[Fetch] --> C
      \""", block: Block.bordered(title: "Flow"), scroll: {row, column})

  The source is parsed once, in `new/2`, and laid out at the area's
  width each time the widget is drawn: labels wrap narrower when the
  diagram would be wider than the area. What still doesn't fit is cut;
  `:scroll` moves it. Source Mermaid can't draw is shown as it is, under
  the error.

  To draw a diagram every frame without laying it out again, keep
  `to_text/2` for the current width and draw it with
  `Elui.Widgets.Paragraph`.
  """

  alias Elui.Buffer
  alias Elui.Layout.Rect
  alias Elui.Style
  alias Elui.Text
  alias Elui.Text.{Line, Span}
  alias Elui.Widgets.{Block, Paragraph}

  defstruct diagram: nil,
            error: nil,
            source: "",
            block: nil,
            style: %Style{},
            scroll: {0, 0},
            render: []

  @type t :: %__MODULE__{}

  @doc """
  Creates the widget from Mermaid source.

  Options:

    * `:block` - an `Elui.Widgets.Block` drawn around the diagram
    * `:style` - base style
    * `:scroll` - `{rows, columns}` to skip, or just rows (default 0)
    * `:styles`, `:ascii`, `:max_label_width` - as for
      `Elui.Mermaid.render/2`
  """
  @spec new(String.t(), Keyword.t()) :: t()
  def new(source, opts \\ []) when is_binary(source) do
    {diagram, error} =
      case Elui.Mermaid.parse(source) do
        {:ok, diagram} -> {diagram, nil}
        {:error, message} -> {nil, message}
      end

    %__MODULE__{
      diagram: diagram,
      error: error,
      source: source,
      block: Keyword.get(opts, :block),
      style: Style.to_style(Keyword.get(opts, :style)),
      scroll: scroll(Keyword.get(opts, :scroll, 0)),
      render: Keyword.take(opts, [:styles, :ascii, :max_label_width])
    }
  end

  defp scroll(rows) when is_integer(rows) and rows >= 0, do: {rows, 0}

  defp scroll({rows, columns} = scroll)
       when is_integer(rows) and rows >= 0 and is_integer(columns) and columns >= 0,
       do: scroll

  defp scroll(value) do
    raise ArgumentError,
          "Mermaid :scroll must be rows or {rows, columns}, got: #{inspect(value)}"
  end

  @doc "The text the widget draws at `width` columns, before scrolling."
  @spec to_text(t(), non_neg_integer()) :: Text.t()
  def to_text(%__MODULE__{error: nil} = mermaid, width) do
    case Elui.Mermaid.render(mermaid.diagram, Keyword.put(mermaid.render, :width, width)) do
      {:ok, lines} -> Text.new(lines)
      {:error, message} -> to_text(%{mermaid | error: message}, width)
    end
  end

  def to_text(%__MODULE__{} = mermaid, _width) do
    error = %Line{spans: [Span.new("Mermaid: " <> mermaid.error, fg: :light_red)]}

    source =
      mermaid.source |> String.trim_trailing() |> String.split("\n") |> Enum.map(&Line.raw/1)

    Text.new([error | source])
  end

  @doc "Number of rows the widget needs at the given width."
  @spec line_count(t(), non_neg_integer()) :: non_neg_integer()
  def line_count(%__MODULE__{} = mermaid, width), do: mermaid |> to_text(width) |> Text.height()

  @doc false
  def render_into(%__MODULE__{} = mermaid, %Rect{} = area, %Buffer{} = buffer) do
    buffer = Buffer.set_style(buffer, area, mermaid.style)
    {inner, buffer} = Block.render_with_block(mermaid.block, area, buffer)

    if Rect.empty?(inner) do
      buffer
    else
      mermaid
      |> to_text(inner.width)
      |> Paragraph.new(scroll: mermaid.scroll)
      |> Paragraph.render_into(inner, buffer)
    end
  end

  defimpl Elui.Widget do
    def render(mermaid, area, buffer), do: Elui.Widgets.Mermaid.render_into(mermaid, area, buffer)
  end
end

defmodule Elui.Widgets.Paragraph do
  @moduledoc """
  Displays styled, optionally wrapped, optionally scrolled text.
  Mirrors ratatui's `Paragraph`.

  ## Example

      Paragraph.new("Hello, world!\\nSecond line",
        block: Block.bordered(title: "Greeting"),
        alignment: :center,
        wrap: [trim: true]
      )
  """

  alias Elui.Buffer
  alias Elui.Layout.Rect
  alias Elui.Style
  alias Elui.Text
  alias Elui.Text.{Line, Span, Width, Wrap}
  alias Elui.Widgets.Block

  defstruct text: %Text{},
            block: nil,
            style: %Style{},
            alignment: nil,
            wrap: nil,
            scroll: {0, 0}

  @type t :: %__MODULE__{}

  @doc """
  Creates a paragraph from any text-like value.

  Options:

    * `:block` - an `Elui.Widgets.Block` drawn around the text
    * `:style` - base style
    * `:alignment` - `:left`, `:center` or `:right`
    * `:wrap` - `true` or `[trim: boolean]` to enable word wrapping
    * `:scroll` - `{y, x}` offset (rows, columns), like ratatui
  """
  @spec new(term(), Keyword.t()) :: t()
  def new(text, opts \\ []) do
    %__MODULE__{
      text: Text.to_text(text),
      block: Keyword.get(opts, :block),
      style: Style.to_style(Keyword.get(opts, :style)),
      alignment: Keyword.get(opts, :alignment),
      wrap: Keyword.get(opts, :wrap),
      scroll: Keyword.get(opts, :scroll, {0, 0})
    }
  end

  @doc "Number of rows needed to render the paragraph at the given width."
  @spec line_count(t(), non_neg_integer()) :: non_neg_integer()
  def line_count(%__MODULE__{} = paragraph, width) do
    paragraph.text.lines
    |> Enum.flat_map(&wrap_line(&1, paragraph.wrap, width))
    |> length()
  end

  @doc false
  def render_into(%__MODULE__{} = paragraph, %Rect{} = area, %Buffer{} = buffer) do
    buffer = Buffer.set_style(buffer, area, paragraph.style)
    {inner, buffer} = Block.render_with_block(paragraph.block, area, buffer)

    if Rect.empty?(inner) do
      buffer
    else
      {scroll_y, scroll_x} = paragraph.scroll

      lines =
        paragraph.text.lines
        |> Enum.map(&inherit_style(&1, paragraph))
        |> Enum.flat_map(&wrap_line(&1, paragraph.wrap, inner.width))
        |> Enum.drop(scroll_y)
        |> Enum.take(inner.height)

      lines
      |> Enum.with_index()
      |> Enum.reduce(buffer, fn {line, i}, buf ->
        line = apply_alignment(line, paragraph)
        line = hscroll(line, scroll_x)
        {buf, _} = Buffer.set_line(buf, inner.x, inner.y + i, line, inner.width)
        buf
      end)
    end
  end

  defp inherit_style(%Line{} = line, %__MODULE__{} = paragraph) do
    style =
      paragraph.style
      |> Style.patch(paragraph.text.style)
      |> Style.patch(line.style)

    %{line | style: style}
  end

  defp apply_alignment(%Line{alignment: nil} = line, paragraph) do
    %{line | alignment: paragraph.alignment || paragraph.text.alignment}
  end

  defp apply_alignment(line, _paragraph), do: line

  # -- horizontal scrolling ---------------------------------------------------

  defp hscroll(line, 0), do: line

  defp hscroll(%Line{} = line, offset) do
    {spans, _} =
      Enum.reduce(line.spans, {[], offset}, fn span, {acc, remaining} ->
        w = Span.width(span)

        cond do
          remaining <= 0 -> {[span | acc], 0}
          w <= remaining -> {acc, remaining - w}
          true -> {[drop_columns(span, remaining) | acc], 0}
        end
      end)

    %{line | spans: Enum.reverse(spans)}
  end

  defp drop_columns(%Span{} = span, n) do
    {content, _} =
      span.content
      |> String.graphemes()
      |> Enum.reduce({"", n}, fn g, {acc, remaining} ->
        w = Width.grapheme_width(g)

        if remaining > 0 do
          {acc, remaining - w}
        else
          {acc <> g, 0}
        end
      end)

    %{span | content: content}
  end

  # -- wrapping ---------------------------------------------------------------

  defp wrap_line(line, nil, _width), do: [line]
  defp wrap_line(line, false, _width), do: [line]

  defp wrap_line(line, wrap, width) when width > 0 do
    trim = wrap == true || Keyword.get(List.wrap(wrap), :trim, false)

    line.spans
    |> Wrap.spans(width, trim)
    |> Enum.map(&%Line{spans: &1, style: line.style, alignment: line.alignment})
  end

  defp wrap_line(line, _wrap, _width), do: [line]

  defimpl Elui.Widget do
    def render(paragraph, area, buffer) do
      Elui.Widgets.Paragraph.render_into(paragraph, area, buffer)
    end
  end
end

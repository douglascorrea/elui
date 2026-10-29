defmodule Elui.Widgets.Markdown do
  @moduledoc """
  Draws Markdown: headings, emphasis, code, links, lists and task lists,
  quotes, tables and rules, word-wrapped to the area's width, and
  ` ```mermaid ` blocks as diagrams (`Elui.Mermaid`).

  Wrapping keeps each line in its place: a list item's lines hang under
  its text, every line of a quote keeps its bar, and a table too wide for
  the area narrows its widest columns and wraps their cells. A diagram
  too wide even with its labels wrapped shows its source instead.

  ## Example

      Markdown.new(\"""
      # Release notes

      - **Faster** start-up
      - [ ] Docs for `TextInput`
      \""", block: Block.bordered(title: "Notes"), scroll: offset)

  `new/2` parses a string each time it is called. To draw a long
  document every frame, parse it once with `Elui.Markdown.parse/1` and
  pass the blocks instead. Drawing lays out the blocks down to the
  bottom of the area, so for a very long document scrolled far down,
  keep `to_text/2` for the current width and draw it with
  `Elui.Widgets.Paragraph` (without `:wrap`).

  ## Styles

  The `:styles` option overrides any of these, each a keyword list or an
  `Elui.Style`:

    * `:heading` - heading text (default: cyan, bold)
    * `:emphasis`, `:strong`, `:strikethrough` - italic, bold, crossed out
    * `:code` - inline code (default: yellow)
    * `:code_block` - fenced and indented code (default: yellow)
    * `:link` - link text (default: blue, underlined)
    * `:url` - the URL shown after a link (default: dark gray)
    * `:quote` - text in a quote (default: italic)
    * `:marker` - heading `#`s, list bullets and numbers, task boxes
      (default: dark gray)
    * `:border` - quote bars, rules and table lines (default: dark gray)
    * `:table_header` - header cells (default: bold)

  `theme_styles/1` builds them from an `Elui.Theme`.
  """

  alias Elui.Buffer
  alias Elui.Layout.Rect
  alias Elui.Style
  alias Elui.Text
  alias Elui.Text.{Line, Span, Wrap}
  alias Elui.Theme
  alias Elui.Widgets.Block

  defstruct blocks: [],
            block: nil,
            style: %Style{},
            styles: %{},
            scroll: 0,
            show_urls: true,
            mermaid: []

  @type t :: %__MODULE__{}

  @default_styles %{
    heading: [fg: :cyan, add_modifier: [:bold]],
    emphasis: [add_modifier: [:italic]],
    strong: [add_modifier: [:bold]],
    strikethrough: [add_modifier: [:crossed_out]],
    code: [fg: :yellow],
    code_block: [fg: :yellow],
    link: [fg: :blue, add_modifier: [:underlined]],
    url: [fg: :dark_gray],
    quote: [add_modifier: [:italic]],
    marker: [fg: :dark_gray],
    border: [fg: :dark_gray],
    table_header: [add_modifier: [:bold]]
  }

  # A bullet for each level of nesting, repeating after the third.
  @bullets ["•", "◦", "▪"]

  @doc """
  Creates the widget from a Markdown string, or from blocks returned by
  `Elui.Markdown.parse/1`.

  Options:

    * `:block` - an `Elui.Widgets.Block` drawn around the text
    * `:style` - base style
    * `:styles` - styles for the parts of the text (see above)
    * `:scroll` - rows to skip from the top (default 0)
    * `:show_urls` - shows a link's URL after its text, as
      `text (url)`, unless the text is the URL (default `true`)
    * `:mermaid` - `false` shows ` ```mermaid ` blocks as code; a keyword
      list passes `:styles`, `:ascii` and `:max_label_width` to
      `Elui.Mermaid.render/2` (default `[]`: diagrams in their default
      styles)
  """
  @spec new(String.t() | [Elui.Markdown.block()], Keyword.t()) :: t()
  def new(markdown, opts \\ []) do
    blocks = if is_binary(markdown), do: Elui.Markdown.parse(markdown), else: markdown

    styles =
      Map.merge(
        Map.new(@default_styles, fn {key, style} -> {key, Style.to_style(style)} end),
        Map.new(Keyword.get(opts, :styles, []), fn {key, style} ->
          {key, Style.to_style(style)}
        end)
      )

    %__MODULE__{
      blocks: blocks,
      block: Keyword.get(opts, :block),
      style: Style.to_style(Keyword.get(opts, :style)),
      styles: styles,
      scroll: scroll(Keyword.get(opts, :scroll, 0)),
      show_urls: Keyword.get(opts, :show_urls, true),
      mermaid: mermaid(Keyword.get(opts, :mermaid, []))
    }
  end

  defp mermaid(true), do: []
  defp mermaid(false), do: false

  defp mermaid(opts) when is_list(opts),
    do: Keyword.take(opts, [:styles, :ascii, :max_label_width])

  defp scroll(rows) when is_integer(rows) and rows >= 0, do: rows

  defp scroll(value) do
    raise ArgumentError, "Markdown :scroll must be a number of rows, got: #{inspect(value)}"
  end

  @doc """
  Styles for the `:styles` option from a theme's roles: `:title` for
  headings, `:success` for code, `:accent` (underlined) for links,
  `:muted` for URLs and markers, and `:border` for lines.
  """
  @spec theme_styles(Theme.t()) :: Keyword.t()
  def theme_styles(%Theme{} = theme) do
    code = Theme.style(theme, :success)
    muted = Theme.style(theme, :muted)

    [
      heading: Theme.style(theme, :title),
      code: code,
      code_block: code,
      link: theme |> Theme.style(:accent) |> Style.add_modifier(:underlined),
      url: muted,
      marker: muted,
      border: Theme.style(theme, :border)
    ]
  end

  @doc "The text the widget draws at `width` columns, before scrolling."
  @spec to_text(t(), non_neg_integer()) :: Text.t()
  def to_text(%__MODULE__{} = markdown, width),
    do: markdown |> lines(width) |> Enum.to_list() |> Text.new()

  @doc "Number of rows the widget needs at the given width."
  @spec line_count(t(), non_neg_integer()) :: non_neg_integer()
  def line_count(%__MODULE__{} = markdown, width), do: markdown |> lines(width) |> Enum.count()

  @doc false
  def render_into(%__MODULE__{} = markdown, %Rect{} = area, %Buffer{} = buffer) do
    buffer = Buffer.set_style(buffer, area, markdown.style)
    {inner, buffer} = Block.render_with_block(markdown.block, area, buffer)

    if Rect.empty?(inner) do
      buffer
    else
      markdown
      |> lines(inner.width)
      |> Stream.drop(markdown.scroll)
      |> Enum.take(inner.height)
      |> Enum.with_index()
      |> Enum.reduce(buffer, fn {line, i}, buffer ->
        line = %{line | style: Style.patch(markdown.style, line.style)}
        {buffer, _} = Buffer.set_line(buffer, inner.x, inner.y + i, line, inner.width)
        buffer
      end)
    end
  end

  # Lazy, so drawing lays out only the blocks above the area's bottom edge.
  defp lines(markdown, width) do
    context = %{
      styles: markdown.styles,
      show_urls: markdown.show_urls,
      mermaid: markdown.mermaid,
      base: %Style{},
      depth: 0
    }

    markdown.blocks
    |> Stream.map(&block(&1, max(width, 1), context))
    |> Stream.intersperse([%Line{}])
    |> Stream.concat()
  end

  # -- blocks -------------------------------------------------------------------

  # Blocks `gap` blank lines apart: one, or none in a tight list's items.
  # Deep nesting can leave no room; a block still gets a column.
  defp blocks(blocks, width, context, gap) do
    blocks
    |> Enum.map(&block(&1, max(width, 1), context))
    |> Enum.intersperse(List.duplicate(%Line{}, gap))
    |> Enum.concat()
  end

  defp block({:paragraph, inlines}, width, context) do
    inlines |> spans(context.base, context) |> wrap(width)
  end

  defp block({:heading, level, inlines}, width, context) do
    marker = Span.new(String.duplicate("#", level) <> " ", style(context, :marker))

    inlines
    |> spans(style(context, :heading), context)
    |> wrap(width - Span.width(marker))
    |> hang(marker)
  end

  # A diagram, indented as code is; its source when it doesn't fit.
  defp block({:code_block, "mermaid", lines}, width, %{mermaid: opts} = context)
       when opts != false do
    room = width - 2

    case Elui.Mermaid.render(Enum.join(lines, "\n"), Keyword.put(opts, :width, room)) do
      {:ok, diagram} ->
        if diagram != [] and Enum.all?(diagram, &(Line.width(&1) <= room)),
          do: Enum.map(diagram, &prefix(&1, Span.raw("  "))),
          else: block({:code_block, "", lines}, width, context)

      {:error, _message} ->
        block({:code_block, "", lines}, width, context)
    end
  end

  defp block({:code_block, _language, lines}, width, context) do
    indent = Span.raw("  ")
    style = style(context, :code_block)

    lines
    |> Enum.flat_map(fn line ->
      line |> Wrap.chop(width - 2) |> Enum.map(&%Line{spans: [indent, Span.new(&1, style)]})
    end)
    |> case do
      [] -> [%Line{spans: [indent]}]
      lines -> lines
    end
  end

  defp block({:quote, blocks}, width, context) do
    bar = Span.new("│ ", style(context, :border))

    case blocks(blocks, width - 2, %{context | base: style(context, :quote)}, 1) do
      [] -> [%Line{spans: [bar]}]
      lines -> Enum.map(lines, &prefix(&1, bar))
    end
  end

  defp block({:list, start, tight, items}, width, context) do
    gap = if tight, do: 0, else: 1
    number_width = if start, do: String.length("#{start + length(items) - 1}.")
    nested = %{context | depth: context.depth + 1}

    items
    |> Enum.with_index()
    |> Enum.map(fn {{:item, task, blocks}, index} ->
      marker =
        Span.new(marker(start, index, number_width, task, context.depth), style(context, :marker))

      blocks |> blocks(width - Span.width(marker), nested, gap) |> hang(marker)
    end)
    |> Enum.intersperse(List.duplicate(%Line{}, gap))
    |> Enum.concat()
  end

  defp block({:table, aligns, header, rows}, width, context) do
    border = style(context, :border)
    header = Enum.map(header, &spans(&1, style(context, :table_header), context))
    rows = Enum.map(rows, fn row -> Enum.map(row, &spans(&1, context.base, context)) end)
    widths = column_widths([header | rows], width)
    rule = widths |> Enum.map_join("─┼─", &String.duplicate("─", &1)) |> Span.new(border)

    table_row(header, widths, aligns, border) ++
      [%Line{spans: [rule]}] ++ Enum.flat_map(rows, &table_row(&1, widths, aligns, border))
  end

  defp block(:rule, width, context) do
    [%Line{spans: [Span.new(String.duplicate("─", width), style(context, :border))]}]
  end

  defp style(context, key), do: Style.patch(context.base, context.styles[key])

  defp marker(nil, _index, _number_width, nil, depth), do: Enum.at(@bullets, rem(depth, 3)) <> " "
  defp marker(nil, _index, _number_width, task, _depth), do: box(task)

  defp marker(start, index, number_width, task, _depth) do
    number = String.pad_leading("#{start + index}.", number_width) <> " "
    if task, do: number <> box(task), else: number
  end

  defp box(:todo), do: "[ ] "
  defp box(:done), do: "[x] "

  # Puts `first` before the first line and its width in spaces before the rest.
  defp hang([], first), do: [%Line{spans: [first]}]

  defp hang([line | lines], first) do
    indent = Span.raw(String.duplicate(" ", Span.width(first)))
    [prefix(line, first) | Enum.map(lines, &prefix(&1, indent))]
  end

  defp prefix(%Line{} = line, span), do: %{line | spans: [span | line.spans]}

  # -- tables -------------------------------------------------------------------

  # Columns as wide as their widest cell; when they don't fit, narrow
  # columns keep their width and the wide ones share what is left.
  defp column_widths(rows, width) do
    natural =
      Enum.zip_with(rows, fn cells ->
        cells |> Enum.map(&natural_width/1) |> Enum.max() |> max(1)
      end)

    room = width - 3 * (length(natural) - 1)

    if Enum.sum(natural) <= room do
      natural
    else
      {fitted, _room, _left} =
        natural
        |> Enum.with_index()
        |> Enum.sort()
        |> Enum.reduce({%{}, max(room, length(natural)), length(natural)}, fn {wanted, i},
                                                                              {fitted, room, left} ->
          fit = wanted |> min(div(room, left)) |> max(1)
          {Map.put(fitted, i, fit), room - fit, left - 1}
        end)

      Enum.map(0..(length(natural) - 1)//1, &fitted[&1])
    end
  end

  defp natural_width(chunks) do
    chunks
    |> segments()
    |> Enum.map(fn spans -> spans |> Enum.map(&Span.width/1) |> Enum.sum() end)
    |> Enum.max()
  end

  defp table_row(cells, widths, aligns, border) do
    columns =
      Enum.zip_with([cells, widths, aligns], fn [cell, width, align] ->
        {wrap(cell, width), width, align}
      end)

    height = columns |> Enum.map(fn {lines, _width, _align} -> length(lines) end) |> Enum.max()
    separator = [Span.new(" │ ", border)]

    for row <- 0..(height - 1)//1 do
      spans =
        columns
        |> Enum.map(fn {lines, width, align} ->
          pad(Enum.at(lines, row, %Line{}), width, align)
        end)
        |> Enum.intersperse(separator)
        |> Enum.concat()

      %Line{spans: spans}
    end
  end

  defp pad(%Line{spans: spans} = line, width, align) do
    room = max(width - Line.width(line), 0)

    {left, right} =
      case align do
        :right -> {room, 0}
        :center -> {div(room, 2), room - div(room, 2)}
        _left -> {0, room}
      end

    spaces(left) ++ spans ++ spaces(right)
  end

  defp spaces(0), do: []
  defp spaces(n), do: [Span.raw(String.duplicate(" ", n))]

  # -- inlines ------------------------------------------------------------------

  # Spans for inlines, with `:break` where a hard line break is.
  defp spans(inlines, style, context) do
    Enum.flat_map(inlines, fn
      {:text, text} ->
        [Span.new(text, style)]

      {:code, code} ->
        [Span.new(code, Style.patch(style, context.styles.code))]

      {kind, inner} when kind in [:emphasis, :strong, :strikethrough] ->
        spans(inner, Style.patch(style, context.styles[kind]), context)

      {:link, inner, url} ->
        spans(inner, Style.patch(style, context.styles.link), context) ++
          url(Elui.Markdown.text(inner), url, style, context)

      {:image, alt, url} ->
        label = if alt == "", do: "[image]", else: "[image: #{alt}]"

        [
          Span.new(label, Style.patch(style, context.styles.link))
          | url(label, url, style, context)
        ]

      :line_break ->
        [:break]
    end)
  end

  defp url(text, url, style, context) do
    if context.show_urls and url not in ["", text, "mailto:" <> text],
      do: [Span.new(" (#{url})", Style.patch(style, context.styles.url))],
      else: []
  end

  # -- wrapping -----------------------------------------------------------------

  # Word-wraps spans to `width` columns; every `:break` starts a new line.
  defp wrap(chunks, width) do
    chunks
    |> segments()
    |> Enum.flat_map(fn spans -> spans |> Wrap.spans(width) |> Enum.map(&%Line{spans: &1}) end)
  end

  defp segments(chunks) do
    {segments, current} =
      Enum.reduce(chunks, {[], []}, fn
        :break, {segments, current} -> {[Enum.reverse(current) | segments], []}
        span, {segments, current} -> {segments, [span | current]}
      end)

    Enum.reverse([Enum.reverse(current) | segments])
  end

  defimpl Elui.Widget do
    def render(markdown, area, buffer),
      do: Elui.Widgets.Markdown.render_into(markdown, area, buffer)
  end
end

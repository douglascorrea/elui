defmodule Elui.Mermaid do
  @moduledoc """
  Draws Mermaid diagrams as text, in box-drawing characters: no
  JavaScript, no browser, nothing to install.

      Elui.Mermaid.render(\"""
      flowchart TD
        A[Start] --> B{Is it working?}
        B -->|Yes| C[Ship it]
        B -->|No| D[Debug] --> B
      \""")
      #=> {:ok, [%Elui.Text.Line{}, ...]}

  It reads the diagrams coding agents and READMEs use most:

    * flowcharts (`flowchart` and `graph`) in every direction (`TD`,
      `LR`, `BT`, `RL`): node shapes, solid, thick, dotted and invisible
      links with arrows, crosses or circles at either end, link labels,
      longer links (`--->`), chains (`A --> B --> C`), `&` groups,
      subgraphs, and `<br>`, entity codes and markdown strings in labels.
      `classDef`, `style` and `click` are read and ignored.
    * sequence diagrams (`sequenceDiagram`): participants and actors,
      messages of every arrow type, self messages, notes, activations,
      `autonumber`, and `loop`, `alt`/`else`, `opt`, `par`/`and`,
      `critical`/`option`, `break` and `rect` blocks.

  Flowcharts are laid out in layers the way Mermaid's own layout (dagre)
  does it, on a grid of character cells.

  ## Styles

  The `:styles` option of `render/2` overrides any of these, each a
  keyword list or an `Elui.Style`:

    * `:node` - node borders, participant boxes (default: cyan)
    * `:label` - text in nodes and participant boxes
    * `:edge` - links, messages and their arrowheads (default: gray)
    * `:edge_label` - text on links and messages (default: yellow)
    * `:cluster` - subgraph boxes and block frames (default: dark gray)
    * `:cluster_title` - subgraph titles and block labels (default: bold)
    * `:lifeline` - sequence diagram lifelines (default: dark gray)
    * `:note` - notes (default: light yellow)
    * `:title` - the title from front matter (default: bold)
  """

  alias Elui.Mermaid.{Draw, Flowchart, Grid, Layout, Sequence}
  alias Elui.Style
  alias Elui.Text.{Line, Span}

  @typedoc "A parsed diagram, from `parse/1`, for `render/2`."
  @type diagram :: {:flowchart, term()} | {:sequence, term()}

  @default_styles %{
    node: [fg: :cyan],
    label: [],
    edge: [fg: :gray],
    edge_label: [fg: :yellow],
    cluster: [fg: :dark_gray],
    cluster_title: [add_modifier: [:bold]],
    lifeline: [fg: :dark_gray],
    note: [fg: :light_yellow],
    title: [add_modifier: [:bold]]
  }

  # The narrowest labels get when a diagram is fitted to a width.
  @narrowest 8

  # The most cells a drawing may take, so a huge diagram is an error
  # rather than all the memory.
  @max_cells 500_000

  @doc """
  Parses Mermaid source into a diagram for `render/2`; `{:error,
  message}` for a diagram type it doesn't draw or source it can't read.
  """
  @spec parse(String.t()) :: {:ok, {diagram(), String.t() | nil}} | {:error, String.t()}
  def parse(source) when is_binary(source) do
    if String.valid?(source), do: parse_valid(source), else: {:error, "the source is not UTF-8"}
  end

  defp parse_valid(source) do
    # `%%{init: …}%%` directives, over as many lines as they take, and
    # comments are kept as blank lines so errors give the right line.
    source =
      Regex.replace(~r/%%\{.*?\}%%/s, String.replace(source, "\r\n", "\n"), fn directive ->
        String.duplicate("\n", length(String.split(directive, "\n")) - 1)
      end)

    {title, lines} = source |> String.split("\n") |> front_matter()

    lines =
      Enum.map(lines, fn {line, n} ->
        {if(String.trim_leading(line) =~ ~r/^%%/, do: "", else: line), n}
      end)

    case Enum.drop_while(lines, fn {line, _n} -> String.trim(line) == "" end) do
      [] ->
        {:error, "no diagram"}

      [{first, n} | rest] ->
        body = Enum.map_join(rest, "\n", &elem(&1, 0))
        first = String.trim_leading(first)
        [keyword | _] = String.split(first, ~r/[\s;]/, parts: 2)
        after_keyword = String.slice(first, String.length(keyword)..-1//1) <> "\n" <> body

        result =
          case keyword do
            word when word in ["flowchart", "graph", "flowchart-elk"] ->
              with {:ok, chart} <- Flowchart.parse(after_keyword, n),
                   do: {:ok, {:flowchart, chart}}

            "sequenceDiagram" ->
              with {:ok, diagram} <- Sequence.parse(after_keyword, n) do
                {:ok, {:sequence, %{diagram | title: title || diagram.title}}}
              end

            other ->
              {:error, "#{inspect(other)} diagrams are not supported"}
          end

        with {:ok, diagram} <- result, do: {:ok, {diagram, title(diagram, title)}}
    end
  end

  @doc """
  Draws Mermaid source, or a diagram from `parse/1`, as lines of text.

  Options:

    * `:styles` - styles for the parts of the diagram (see above)
    * `:ascii` - draws with `+`, `-`, `|` and `>` instead of box-drawing
      characters (default `false`)
    * `:max_label_width` - the widest a label gets before it wraps
      (default 30)
    * `:width` - when the diagram is wider than this, labels wrap
      narrower to fit it, as far as they can
  """
  @spec render(String.t() | {diagram(), String.t() | nil}, Keyword.t()) ::
          {:ok, [Line.t()]} | {:error, String.t()}
  def render(source, opts \\ [])

  def render(source, opts) when is_binary(source) do
    with {:ok, diagram} <- parse(source), do: render(diagram, opts)
  end

  def render({diagram, title}, opts) do
    styles = styles(Keyword.get(opts, :styles, []))
    widest = Keyword.get(opts, :max_label_width, 30)

    result =
      case Keyword.get(opts, :width) do
        nil -> draw(diagram, widest, opts, styles)
        width -> fit(diagram, widest, width, opts, styles)
      end

    title =
      if title in [nil, ""],
        do: [],
        else: [%Line{spans: [Span.new(title, styles.title)]}, %Line{}]

    with {:ok, lines} <- result, do: {:ok, title ++ lines}
  end

  @doc "Like `render/2`, but raises on source it can't read."
  @spec render!(String.t() | {diagram(), String.t() | nil}, Keyword.t()) :: [Line.t()]
  def render!(source, opts \\ []) do
    case render(source, opts) do
      {:ok, lines} -> lines
      {:error, message} -> raise ArgumentError, "Mermaid: " <> message
    end
  end

  # Narrower labels until the drawing fits.
  defp fit(diagram, widest, width, opts, styles) do
    with {:ok, lines} <- draw(diagram, widest, opts, styles) do
      if widest <= @narrowest or drawn_width(lines) <= width,
        do: {:ok, lines},
        else: fit(diagram, max(div(widest * 2, 3), @narrowest), width, opts, styles)
    end
  end

  defp drawn_width(lines), do: lines |> Enum.map(&Line.width/1) |> Enum.max(fn -> 0 end)

  defp draw({:flowchart, chart}, widest, opts, styles) do
    geometry = Layout.run(chart, max_label_width: widest)

    if geometry.width * geometry.height > @max_cells do
      {:error, "the diagram is too large to draw"}
    else
      lines =
        geometry
        |> Draw.flowchart(ascii: Keyword.get(opts, :ascii, false))
        |> Grid.to_lines(styles)

      {:ok, lines}
    end
  end

  defp draw({:sequence, diagram}, widest, opts, styles) do
    draw_opts = [
      max_label_width: widest,
      ascii: Keyword.get(opts, :ascii, false),
      max_cells: @max_cells
    ]

    with {:ok, grid} <- Sequence.draw(diagram, draw_opts), do: {:ok, Grid.to_lines(grid, styles)}
  end

  defp title({:sequence, diagram}, _title), do: diagram.title
  defp title(_diagram, title), do: title

  defp styles(overrides) do
    Map.merge(
      Map.new(@default_styles, fn {key, style} -> {key, Style.to_style(style)} end),
      Map.new(overrides, fn {key, style} -> {key, Style.to_style(style)} end)
    )
  end

  # `---` front matter: its `title:` is drawn above the diagram.
  defp front_matter(lines) do
    numbered = Enum.with_index(lines, 1)

    case Enum.drop_while(numbered, fn {line, _n} -> String.trim(line) == "" end) do
      [{first, _n} | after_open] when is_binary(first) ->
        front_matter(String.trim(first) == "---", after_open, numbered)

      _ ->
        {nil, numbered}
    end
  end

  defp front_matter(false, _after_open, numbered), do: {nil, numbered}

  defp front_matter(true, after_open, numbered) do
    case Enum.split_while(after_open, fn {line, _n} -> String.trim(line) != "---" end) do
      {matter, [_close | body]} ->
        title =
          Enum.find_value(matter, fn {line, _n} ->
            case Regex.run(~r/^\s*title:\s*(.*?)\s*$/, line) do
              [_, title] -> title |> String.trim("\"") |> String.trim("'")
              nil -> nil
            end
          end)

        {title, body}

      {_matter, []} ->
        {nil, numbered}
    end
  end
end

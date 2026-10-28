defmodule Elui.Mermaid.Label do
  @moduledoc false

  # The text of a Mermaid node, edge or note: `<br>` breaks the line,
  # `<b>`, `<strong>`, `<i>` and `<em>` style it, entity codes (`#quot;`,
  # `#9829;`, `&amp;`) stand for characters, and a "markdown string"
  # (backticks inside the quotes) reads `**bold**` and `*italics*` and
  # breaks lines where the source does.

  alias Elui.Style
  alias Elui.Text.{Span, Wrap}

  @entities %{
    "quot" => "\"",
    "amp" => "&",
    "lt" => "<",
    "gt" => ">",
    "apos" => "'",
    "nbsp" => " ",
    "semi" => ";",
    "colon" => ":",
    "num" => "#",
    "hellip" => "…",
    "mdash" => "—",
    "ndash" => "–",
    "rarr" => "→",
    "larr" => "←",
    "harr" => "↔",
    "uarr" => "↑",
    "darr" => "↓",
    "rArr" => "⇒",
    "lArr" => "⇐",
    "hArr" => "⇔",
    "check" => "✓",
    "times" => "×",
    "divide" => "÷",
    "plusmn" => "±",
    "minus" => "−",
    "ne" => "≠",
    "le" => "≤",
    "ge" => "≥",
    "infin" => "∞",
    "deg" => "°",
    "micro" => "µ",
    "bull" => "•",
    "middot" => "·",
    "laquo" => "«",
    "raquo" => "»",
    "lsquo" => "‘",
    "rsquo" => "’",
    "ldquo" => "“",
    "rdquo" => "”",
    "sect" => "§",
    "para" => "¶",
    "euro" => "€",
    "pound" => "£",
    "yen" => "¥",
    "cent" => "¢",
    "hearts" => "♥",
    "star" => "☆",
    "copy" => "©",
    "reg" => "®",
    "trade" => "™"
  }

  @tags %{
    "b" => :bold,
    "strong" => :bold,
    "i" => :italic,
    "em" => :italic,
    "u" => :underlined,
    "s" => :crossed_out,
    "del" => :crossed_out
  }

  @doc "Lines of spans for label text, quotes already taken off."
  @spec parse(String.t()) :: [[Span.t()]]
  def parse(text) do
    case String.trim(text) do
      "" ->
        []

      "`" <> rest = trimmed ->
        if String.ends_with?(rest, "`") and rest != "",
          do: rest |> String.slice(0..-2//1) |> markdown(),
          else: html(trimmed)

      trimmed ->
        html(trimmed)
    end
  end

  @doc "The label's lines word-wrapped to `width` columns."
  @spec wrap([[Span.t()]], pos_integer()) :: [[Span.t()]]
  def wrap(lines, width) do
    Enum.flat_map(lines, fn spans ->
      if spans |> Enum.map(&Span.width/1) |> Enum.sum() <= width,
        do: [spans],
        else: Wrap.spans(spans, width, true)
    end)
  end

  @doc "The width of the widest line."
  @spec width([[Span.t()]]) :: non_neg_integer()
  def width(lines) do
    lines
    |> Enum.map(fn spans -> spans |> Enum.map(&Span.width/1) |> Enum.sum() end)
    |> Enum.max(fn -> 0 end)
  end

  @doc "The label as plain text, its lines joined by `joiner`."
  @spec text([[Span.t()]], String.t()) :: String.t()
  def text(lines, joiner \\ " ") do
    Enum.map_join(lines, joiner, fn spans -> Enum.map_join(spans, & &1.content) end)
  end

  # Mermaid's `#name;` and `#123;` codes and HTML's `&name;` and `&#123;`.
  defp decode(text) do
    Regex.replace(~r/[#&](#?)(x?)([0-9A-Fa-f]+|[A-Za-z]+);/, text, fn whole, hash, hex, code ->
      cond do
        hex == "x" and hash == "#" -> codepoint(String.to_integer(code, 16), whole)
        hex == "" and code =~ ~r/^\d+$/ -> codepoint(String.to_integer(code), whole)
        hash == "" and hex == "" -> Map.get(@entities, code, whole)
        true -> whole
      end
    end)
  end

  defp codepoint(code, whole) do
    if code > 0 and code <= 0x10FFFF and code not in 0xD800..0xDFFF,
      do: <<code::utf8>>,
      else: whole
  end

  # -- text with HTML tags ------------------------------------------------------------------

  defp html(text) do
    ~r{<br\s*/?>}i
    |> Regex.split(text)
    |> Enum.map(&styled/1)
  end

  # Spans for one line, styled by the tags it opens and closes.
  defp styled(line) do
    ~r{<(/?)([a-zA-Z]+)\s*>}
    |> Regex.split(line, include_captures: true)
    |> Enum.reduce({[], []}, fn piece, {spans, open} ->
      case Regex.run(~r{^<(/?)([a-zA-Z]+)\s*>$}, piece) do
        [_, close, tag] when is_map_key(@tags, tag) ->
          modifier = @tags[tag]
          {spans, if(close == "", do: [modifier | open], else: List.delete(open, modifier))}

        _ ->
          {[span(decode(piece), open) | spans], open}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
    |> Enum.reject(&(&1.content == ""))
  end

  defp span(text, []), do: Span.raw(text)
  defp span(text, modifiers), do: Span.new(text, add_modifier: Enum.uniq(modifiers))

  # -- markdown strings ---------------------------------------------------------------------

  defp markdown(text) do
    text
    |> String.split("\n")
    |> Enum.map(fn line ->
      case Elui.Markdown.parse(String.trim(line)) do
        [{:paragraph, inlines}] -> inlines(inlines, %Style{})
        _ -> [Span.raw(decode(String.trim(line)))]
      end
    end)
  end

  defp inlines(inlines, style) do
    Enum.flat_map(inlines, fn
      {:text, text} -> [Span.new(text, style)]
      {:code, code} -> [Span.new(code, style)]
      {:strong, inner} -> inlines(inner, Style.add_modifier(style, :bold))
      {:emphasis, inner} -> inlines(inner, Style.add_modifier(style, :italic))
      {:strikethrough, inner} -> inlines(inner, Style.add_modifier(style, :crossed_out))
      {:link, inner, _url} -> inlines(inner, style)
      {:image, alt, _url} -> [Span.new(alt, style)]
      :line_break -> [Span.raw(" ")]
    end)
  end
end

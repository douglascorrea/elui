defmodule Elui.Text.Wrap do
  @moduledoc false

  # Greedy word wrapping of styled spans by display width, shared by
  # `Elui.Widgets.Paragraph` and `Elui.Widgets.Markdown`.

  alias Elui.Text.{Span, Width}

  @doc """
  Word-wraps spans to `width` columns and returns the spans of each line.
  Lines break at spaces, which they drop, and a word wider than the line
  is cut. With `trim` the first line also drops the spaces it starts with.
  Always returns at least one line.
  """
  @spec spans([Span.t()], integer(), boolean()) :: [[Span.t()]]
  def spans(spans, width, trim \\ false) do
    width = max(width, 1)

    words =
      spans
      |> Enum.flat_map(fn span ->
        span.content |> String.graphemes() |> Enum.map(&{&1, span.style})
      end)
      |> Enum.chunk_by(fn {grapheme, _style} -> grapheme == " " end)

    {lines, line, _used} =
      Enum.reduce(words, {[], [], 0}, fn word, {lines, line, used} ->
        word_width =
          word
          |> Enum.map(fn {grapheme, _style} -> Width.grapheme_width(grapheme) end)
          |> Enum.sum()

        cond do
          # Spaces opening a line go when trimming, on a wrapped line, or
          # when they don't fit.
          space?(word) and used == 0 and (trim or lines != [] or word_width > width) ->
            {lines, line, used}

          used + word_width <= width ->
            {lines, [word | line], used + word_width}

          space?(word) ->
            {[line | lines], [], 0}

          word_width <= width ->
            {[line | lines], [word], word_width}

          true ->
            lines = if line == [], do: lines, else: [line | lines]
            {pieces, last, last_width} = cut(word, width)
            {Enum.reduce(pieces, lines, &[[&1] | &2]), [last], last_width}
        end
      end)

    lines = if line == [] and lines != [], do: lines, else: [line | lines]

    lines
    |> Enum.reverse()
    |> Enum.map(fn words ->
      words |> Enum.drop_while(&space?/1) |> Enum.reverse() |> Enum.concat() |> regroup()
    end)
  end

  @doc "Cuts text into pieces of at most `width` columns, keeping its spaces."
  @spec chop(String.t(), integer()) :: [String.t()]
  def chop(text, width) do
    {pieces, last, _used} =
      text |> String.graphemes() |> Enum.map(&{&1, nil}) |> cut(max(width, 1))

    Enum.map(pieces ++ [last], fn piece -> Enum.map_join(piece, &elem(&1, 0)) end)
  end

  defp space?([{" ", _style} | _]), do: true
  defp space?(_word), do: false

  # Cuts a word into pieces of at most `width` columns (a wide character
  # alone may exceed it); returns the full pieces and the last one.
  defp cut(word, width) do
    {pieces, current, used} =
      Enum.reduce(word, {[], [], 0}, fn {grapheme, _style} = pair, {pieces, current, used} ->
        grapheme_width = Width.grapheme_width(grapheme)

        if used + grapheme_width > width and current != [],
          do: {[Enum.reverse(current) | pieces], [pair], grapheme_width},
          else: {pieces, [pair | current], used + grapheme_width}
      end)

    {Enum.reverse(pieces), Enum.reverse(current), used}
  end

  defp regroup(graphemes) do
    graphemes
    |> Enum.chunk_by(fn {_grapheme, style} -> style end)
    |> Enum.map(fn [{_grapheme, style} | _] = chunk ->
      %Span{content: Enum.map_join(chunk, fn {grapheme, _style} -> grapheme end), style: style}
    end)
  end
end

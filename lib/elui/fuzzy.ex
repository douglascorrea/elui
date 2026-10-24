defmodule Elui.Fuzzy do
  @moduledoc """
  An fzf-style matcher for pickers, such as `Elui.Widgets.FilterableSelect`
  with `matcher: :fuzzy`.

  A query is words separated by spaces; an item matches when every word
  does, and a word matches when its characters appear in the item in
  order, not necessarily together (`vbx` matches `vibex`). Smart case: a
  query in lower case ignores case, one with a capital letter does not.

  Matches are ranked: characters close together, ones that start a word
  (after `/ _ - . :` or a space, or a capital after a lower-case letter)
  and a match at the very start score higher; ties go to the shorter item,
  then to the earlier one. `filter/2` returns `{index, positions}` pairs,
  best first. Positions are the byte offsets of the matched characters in
  the item (in the case-folded item when case is ignored), for
  highlighting.

  Items are prepared once (`prepare/1`), so typing re-filters without
  folding case again; a query that only grows re-filters the previous
  matches (`refine/4`).

  ## Example

      entries = Elui.Fuzzy.prepare(["lib/app.ex", "lib/cli.ex", "README.md"])
      Elui.Fuzzy.filter("cli", entries)
      #=> [{1, [4, 5, 6]}]
  """

  @boundary ~c" /_-.:\\\t"

  @typedoc "An item as the matcher keeps it: its index, its text and its case-folded text."
  @type entry :: {non_neg_integer(), String.t(), String.t()}

  @typedoc "A match: the item's index and the byte offsets of its matched characters."
  @type match :: {non_neg_integer(), [non_neg_integer()]}

  @doc "Items as the matcher keeps them: `[{index, text, folded}]`."
  @spec prepare([String.t()]) :: [entry()]
  def prepare(items) do
    items
    |> Enum.with_index()
    |> Enum.map(fn {text, i} -> {i, text, String.downcase(text)} end)
  end

  @doc """
  The prepared `entries` matching `query`, best first:
  `[{index, positions}]`. An empty query keeps every entry, in order.
  """
  @spec filter(String.t(), [entry()]) :: [match()]
  def filter(query, entries) do
    case terms(query) do
      {[], _fold?} ->
        Enum.map(entries, fn {i, _text, _folded} -> {i, []} end)

      {words, fold?} ->
        entries
        |> Enum.flat_map(fn {i, text, folded} ->
          case match_words(words, if(fold?, do: folded, else: text), text) do
            nil -> []
            {score, positions} -> [{{-score, byte_size(text), i}, {i, positions}}]
          end
        end)
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.map(&elem(&1, 1))
    end
  end

  @doc """
  `filter/2` for `query` when `previous` (the query that gave `matches`)
  is a prefix of it with the same case rule: only the earlier matches can
  still match. Falls back to every entry otherwise.
  """
  @spec refine(String.t(), String.t(), [match()], [entry()]) :: [match()]
  def refine(query, previous, matches, entries) do
    {_, fold_now?} = terms(query)
    {_, fold_before?} = terms(previous)

    if previous != "" and String.starts_with?(query, previous) and fold_now? == fold_before? do
      kept = MapSet.new(matches, &elem(&1, 0))
      filter(query, Enum.filter(entries, fn {i, _t, _f} -> MapSet.member?(kept, i) end))
    else
      filter(query, entries)
    end
  end

  @doc "Whether `query` matches `text` at all."
  @spec match?(String.t(), String.t()) :: boolean()
  def match?(query, text) do
    {words, fold?} = terms(query)

    words == [] or
      match_words(words, if(fold?, do: String.downcase(text), else: text), text) != nil
  end

  # The query's words (as lists of graphemes) and whether case is folded.
  defp terms(query) do
    fold? = query == String.downcase(query)

    words =
      query
      |> String.split(" ", trim: true)
      |> Enum.map(&String.graphemes/1)

    {words, fold?}
  end

  defp match_words(words, haystack, original) do
    Enum.reduce_while(words, {0, []}, fn word, {score, positions} ->
      case match_word(word, haystack, original) do
        nil -> {:halt, nil}
        {s, p} -> {:cont, {score + s, positions ++ p}}
      end
    end)
    |> case do
      nil -> nil
      {score, positions} -> {score, positions |> Enum.uniq() |> Enum.sort()}
    end
  end

  # One word: the earliest in-order match, tightened from its end backwards
  # (the shortest span ending there), then scored.
  defp match_word(chars, haystack, original) do
    with [_ | _] = forward <- forward(chars, haystack, 0, []),
         last = List.last(forward),
         start when is_integer(start) <- backward(Enum.reverse(chars), haystack, last + 1),
         [_ | _] = positions <- forward(chars, haystack, start, []) do
      {score(chars, positions, haystack, original), positions}
    else
      _ -> nil
    end
  end

  defp forward([], _haystack, _from, acc), do: Enum.reverse(acc)

  defp forward([g | rest], haystack, from, acc) do
    size = byte_size(haystack)

    if from > size do
      nil
    else
      case :binary.match(haystack, g, scope: {from, size - from}) do
        {pos, len} -> forward(rest, haystack, pos + len, [pos | acc])
        :nomatch -> nil
      end
    end
  end

  # Walking back from `limit`, the latest position of each character in
  # turn: where the tightest match ending at `limit` starts.
  defp backward([], _haystack, limit), do: limit

  defp backward([g | rest], haystack, limit) do
    case :binary.matches(haystack, g, scope: {0, limit}) do
      [] -> nil
      found -> backward(rest, haystack, found |> List.last() |> elem(0))
    end
  end

  defp score(chars, positions, haystack, original) do
    first = hd(positions)
    last = List.last(positions)
    span = last + byte_size(List.last(chars)) - first
    gap = span - Enum.reduce(chars, 0, &(byte_size(&1) + &2))

    consecutive = count_consecutive(positions, chars)
    boundaries = Enum.count(positions, &boundary?(haystack, original, &1))

    16 * length(chars) - 2 * gap + 6 * boundaries + 6 * consecutive +
      if(first == 0, do: 8, else: 0)
  end

  defp count_consecutive(positions, chars) do
    positions
    |> Enum.zip(chars)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.count(fn [{p, g}, {next, _}] -> p + byte_size(g) == next end)
  end

  defp boundary?(_haystack, _original, 0), do: true

  defp boundary?(haystack, original, pos) do
    prev = :binary.at(haystack, pos - 1)

    prev in @boundary or
      (pos < byte_size(original) and
         camel?(:binary.at(original, pos - 1), :binary.at(original, pos)))
  end

  defp camel?(prev, char), do: prev in ?a..?z and char in ?A..?Z
end

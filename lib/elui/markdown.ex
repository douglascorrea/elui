defmodule Elui.Markdown do
  @moduledoc """
  Parses Markdown into blocks for `Elui.Widgets.Markdown` to draw.

  It reads CommonMark's blocks and inlines plus GitHub's tables, task
  lists and strikethrough: the Markdown of READMEs and coding agents. Raw
  HTML stays text, except `<br>`, which breaks the line.

      Elui.Markdown.parse("# Title\\n\\nSome *emphasis*.")
      #=> [
      #=>   {:heading, 1, [{:text, "Title"}]},
      #=>   {:paragraph, [{:text, "Some "}, {:emphasis, [{:text, "emphasis"}]}, {:text, "."}]}
      #=> ]

  ## Blocks

    * `{:heading, level, inlines}` - `level` is 1 to 6
    * `{:paragraph, inlines}`
    * `{:code_block, language, lines}` - `language` is the first word of a
      fence's info string, `""` without one
    * `{:quote, blocks}`
    * `{:list, start, tight, items}` - `start` is `nil` for a bullet list
      and the first number of an ordered one; a `tight` list has no blank
      lines between its items. Each item is `{:item, task, blocks}`, with
      `task` `nil`, `:todo` (`[ ]`) or `:done` (`[x]`)
    * `{:table, aligns, header, rows}` - `aligns` holds `:left`, `:center`,
      `:right` or `nil` per column; `header` is a list of cells, `rows` a
      list of lists of cells, and a cell a list of inlines
    * `:rule`

  ## Inlines

    * `{:text, string}`
    * `{:code, string}`
    * `{:emphasis, inlines}`, `{:strong, inlines}`, `{:strikethrough, inlines}`
    * `{:link, inlines, url}` - inline, reference and `<autolink>` links
    * `{:image, alt, url}`
    * `:line_break` - a hard line break
  """

  @type inline ::
          {:text, String.t()}
          | {:code, String.t()}
          | {:emphasis | :strong | :strikethrough, [inline()]}
          | {:link, [inline()], String.t()}
          | {:image, String.t(), String.t()}
          | :line_break

  @type item :: {:item, :todo | :done | nil, [block()]}

  @type block ::
          {:heading, 1..6, [inline()]}
          | {:paragraph, [inline()]}
          | {:code_block, String.t(), [String.t()]}
          | {:quote, [block()]}
          | {:list, non_neg_integer() | nil, boolean(), [item()]}
          | {:table, [:left | :center | :right | nil], [[inline()]], [[[inline()]]]}
          | :rule

  # ASCII punctuation: what a backslash escapes.
  @escapable Enum.map(Enum.concat([?!..?/, ?:..?@, ?[..?`, ?{..?~]), &<<&1>>)

  @entities %{
    "amp" => "&",
    "lt" => "<",
    "gt" => ">",
    "quot" => "\"",
    "apos" => "'",
    "nbsp" => " ",
    "copy" => "©",
    "reg" => "®",
    "trade" => "™",
    "hellip" => "…",
    "mdash" => "—",
    "ndash" => "–",
    "lsquo" => "‘",
    "rsquo" => "’",
    "ldquo" => "“",
    "rdquo" => "”",
    "laquo" => "«",
    "raquo" => "»",
    "bull" => "•",
    "middot" => "·",
    "times" => "×",
    "divide" => "÷",
    "deg" => "°",
    "larr" => "←",
    "rarr" => "→",
    "uarr" => "↑",
    "darr" => "↓",
    "harr" => "↔"
  }

  @doc "Parses Markdown into blocks."
  @spec parse(String.t()) :: [block()]
  def parse(markdown) when is_binary(markdown) do
    blocks =
      markdown
      |> String.replace(["\r\n", "\r"], "\n")
      |> String.split("\n")
      |> Enum.map(&expand_tabs/1)
      |> blocks()

    # The first definition of a label wins.
    refs = blocks |> definitions() |> Enum.reverse() |> Map.new()
    resolve(blocks, refs)
  end

  @doc "The plain text of inlines, without their formatting."
  @spec text([inline()]) :: String.t()
  def text(inlines) do
    Enum.map_join(inlines, fn
      {:text, text} -> text
      {:code, code} -> code
      {kind, inner} when kind in [:emphasis, :strong, :strikethrough] -> text(inner)
      {:link, inner, _url} -> text(inner)
      {:image, alt, _url} -> alt
      :line_break -> " "
    end)
  end

  defp expand_tabs(line) do
    if String.contains?(line, "\t") do
      line
      |> String.graphemes()
      |> Enum.reduce({[], 0}, fn
        "\t", {acc, column} ->
          spaces = 4 - rem(column, 4)
          {[String.duplicate(" ", spaces) | acc], column + spaces}

        grapheme, {acc, column} ->
          {[grapheme | acc], column + 1}
      end)
      |> elem(0)
      |> Enum.reverse()
      |> IO.iodata_to_binary()
    else
      line
    end
  end

  # -- blocks -------------------------------------------------------------------
  #
  # Blocks are parsed line by line with their inline text left raw; links
  # need every reference definition first, so inlines are parsed last.

  defp blocks(lines), do: lines |> parse_blocks([], false, false) |> elem(0)

  # Also returns whether a blank line separates two of the blocks, which
  # makes the list item holding them loose, and the lines left over: lazy
  # lines (see `lazy?/2`) that no paragraph took.
  defp parse_blocks([], acc, _blank?, loose?), do: {Enum.reverse(acc), loose?, []}

  defp parse_blocks([{:lazy, _line} | _] = lines, acc, _blank?, loose?),
    do: {Enum.reverse(acc), loose?, lines}

  defp parse_blocks([line | rest] = lines, acc, blank?, loose?) do
    if blank?(line) do
      parse_blocks(rest, acc, acc != [], loose?)
    else
      {new, rest} = block(lines)
      parse_blocks(rest, Enum.reverse(new, acc), false, loose? or blank?)
    end
  end

  defp block([line | rest] = lines) do
    cond do
      fence = fence_open(line) -> code_fence(fence, rest)
      heading = atx_heading(line) -> {[heading], rest}
      rule?(line) -> {[:rule], rest}
      quote?(line) -> block_quote(lines)
      item = list_item(line) -> list(lines, item)
      indented?(line) -> indented_code(lines)
      table?(lines) -> table(lines)
      true -> paragraph(lines)
    end
  end

  defp blank?({:lazy, _line}), do: false
  defp blank?(line), do: String.trim(line) == ""

  # Whether a line ends a paragraph instead of continuing it.
  defp interrupts?(line) do
    fence_open(line) != nil or atx_heading(line) != nil or rule?(line) or quote?(line) or
      case list_item(line) do
        nil -> false
        %{empty?: true} -> false
        %{start: start} -> start in [nil, 1]
      end
  end

  defp unindent(line, n) do
    spaces = byte_size(line) - byte_size(String.trim_leading(line, " "))
    drop = min(spaces, n)
    binary_part(line, drop, byte_size(line) - drop)
  end

  # -- code ---------------------------------------------------------------------

  defp fence_open(line) do
    case Regex.run(~r/^( {0,3})(`{3,}|~{3,})(.*)$/, line) do
      [_, indent, marks, info] ->
        if String.starts_with?(marks, "`") and String.contains?(info, "`") do
          nil
        else
          language = info |> String.split() |> List.first() || ""
          {byte_size(indent), marks, language}
        end

      nil ->
        nil
    end
  end

  defp code_fence({indent, marks, language}, rest) do
    char = Regex.escape(String.first(marks))
    closing = Regex.compile!("^ {0,3}#{char}{#{String.length(marks)},} *$")
    {body, rest} = Enum.split_while(rest, &(is_binary(&1) and not Regex.match?(closing, &1)))

    # A lazy line ends the fence with its container, and is not dropped.
    rest =
      case rest do
        [fence | rest] when is_binary(fence) -> rest
        rest -> rest
      end

    {[{:code_block, language, Enum.map(body, &unindent(&1, indent))}], rest}
  end

  defp indented?(line), do: is_binary(line) and String.starts_with?(line, "    ")

  defp indented_code(lines) do
    {body, rest} = Enum.split_while(lines, &(blank?(&1) or indented?(&1)))
    {trailing, body} = body |> Enum.reverse() |> Enum.split_while(&blank?/1)
    code = body |> Enum.reverse() |> Enum.map(&unindent(&1, 4))
    {[{:code_block, "", code}], trailing ++ rest}
  end

  # -- headings and rules -------------------------------------------------------

  defp atx_heading(line) do
    case Regex.run(~r/^ {0,3}(\#{1,6})(?:[ ]+(.*?))?[ ]*$/, line) do
      [_, hashes] -> {:heading, String.length(hashes), ""}
      [_, hashes, text] -> {:heading, String.length(hashes), strip_closing_hashes(text)}
      nil -> nil
    end
  end

  defp strip_closing_hashes(text) do
    ~r/(?:^|[ ]+)\#+[ ]*$/ |> Regex.replace(text, "") |> String.trim()
  end

  defp rule?(line) do
    Regex.match?(~r/^ {0,3}(?:(?:\*[ ]*){3,}|(?:-[ ]*){3,}|(?:_[ ]*){3,})$/, line)
  end

  # -- quotes -------------------------------------------------------------------

  defp quote?(line), do: is_binary(line) and Regex.match?(~r/^ {0,3}>/, line)

  defp block_quote(lines) do
    {inner, _rest} = take_quote(lines, [])
    {blocks, _loose?, left} = parse_blocks(inner, [], false, false)
    # The quote took a line for each of its own; the ones left go back.
    {[{:quote, blocks}], Enum.drop(lines, length(inner) - length(left))}
  end

  defp take_quote([], acc), do: {Enum.reverse(acc), []}

  defp take_quote([line | rest] = lines, acc) do
    cond do
      quote?(line) -> take_quote(rest, [Regex.replace(~r/^ {0,3}> ?/, line, "") | acc])
      lazy?(acc, line) -> take_quote(rest, [{:lazy, unlazy(line)} | acc])
      true -> {Enum.reverse(acc), lines}
    end
  end

  # A lazy line may continue a paragraph without the quote's `>` or the
  # list item's indent. The container takes it marked `{:lazy, line}`, and
  # it ends any block but a paragraph, which goes on with it as text; a
  # lazy line no paragraph takes goes back out of the container.
  defp lazy?([previous | _], line) do
    line = unlazy(line)
    not blank?(previous) and not blank?(line) and not interrupts?(line) and list_item(line) == nil
  end

  defp lazy?([], _line), do: false

  defp unlazy({:lazy, line}), do: line
  defp unlazy(line), do: line

  # -- lists --------------------------------------------------------------------

  defp list_item(line) do
    case Regex.run(~r/^( {0,3})([-+*]|\d{1,9}[.)])( *)(.*)$/, line) do
      [_, indent, marker, spaces, text] when spaces != "" or text == "" ->
        item(byte_size(indent) + byte_size(marker), byte_size(spaces), marker, text)

      _ ->
        nil
    end
  end

  defp item(marker_end, spaces, marker, text) do
    {content_indent, first} =
      cond do
        text == "" -> {marker_end + 1, ""}
        # Five spaces or more start an indented code block in the item.
        spaces > 4 -> {marker_end + 1, String.duplicate(" ", spaces - 1) <> text}
        true -> {marker_end + spaces, text}
      end

    {kind, start} =
      case Integer.parse(marker) do
        {number, delimiter} -> {{:ordered, delimiter}, number}
        :error -> {{:bullet, marker}, nil}
      end

    %{kind: kind, start: start, indent: content_indent, first: first, empty?: text == ""}
  end

  defp list(lines, first) do
    {items, rest, loose?} = take_items(lines, first.kind, [], false)
    {[{:list, first.start, not loose?, items}], rest}
  end

  # Items of one kind (the same bullet, or numbers with the same delimiter);
  # a blank line between two of them, or between two blocks in one, makes
  # the list loose. A lazy line no paragraph in an item took ends the list.
  defp take_items(lines, kind, items, loose?) do
    {blanks, after_blanks} = Enum.split_while(lines, &blank?/1)

    with [line | rest] when is_binary(line) <- after_blanks,
         false <- rule?(line),
         %{kind: ^kind} = item <- list_item(line) do
      {item_lines, _rest} = take_item_lines(rest, item.indent, [item.first])
      {task, item_lines} = task(item_lines)
      {blocks, gap?, left} = parse_blocks(item_lines, [], false, false)
      loose? = loose? or gap? or (items != [] and blanks != [])
      items = [{:item, task, blocks} | items]
      rest = Enum.drop(after_blanks, length(item_lines) - length(left))

      if left == [],
        do: take_items(rest, kind, items, loose?),
        else: {Enum.reverse(items), rest, loose?}
    else
      _ -> {Enum.reverse(items), lines, loose?}
    end
  end

  # The lines after an item's first: those indented to its content (the
  # indent removed), blank lines followed by more of them, and lazy lines.
  defp take_item_lines([], _indent, acc), do: {Enum.reverse(acc), []}

  defp take_item_lines([line | rest] = lines, indent, acc) do
    cond do
      blank?(line) ->
        {blanks, after_blanks} = Enum.split_while(lines, &blank?/1)

        case after_blanks do
          [next | _] ->
            if indented_by?(next, indent),
              do: take_item_lines(after_blanks, indent, Enum.map(blanks, fn _ -> "" end) ++ acc),
              else: {Enum.reverse(acc), lines}

          [] ->
            {Enum.reverse(acc), lines}
        end

      indented_by?(line, indent) ->
        take_item_lines(rest, indent, [unindent(line, indent) | acc])

      lazy?(acc, line) ->
        take_item_lines(rest, indent, [{:lazy, line |> unlazy() |> String.trim_leading()} | acc])

      true ->
        {Enum.reverse(acc), lines}
    end
  end

  defp indented_by?(line, n),
    do: is_binary(line) and String.starts_with?(line, String.duplicate(" ", n))

  defp task([first | rest] = lines) do
    case Regex.run(~r/^\[([ xX])\](?: +(.*))?$/, first) do
      [_, " " | text] -> {:todo, [Enum.join(text) | rest]}
      [_, _done | text] -> {:done, [Enum.join(text) | rest]}
      nil -> {nil, lines}
    end
  end

  # -- tables -------------------------------------------------------------------

  defp table?([header, delimiter | _]) when is_binary(header) and is_binary(delimiter) do
    String.contains?(header, "|") and String.contains?(delimiter, "|") and
      Regex.match?(~r/^ {0,3}\|?[ ]*:?-+:?[ ]*(?:\|[ ]*:?-+:?[ ]*)*\|?[ ]*$/, delimiter) and
      length(cells(header)) == length(cells(delimiter))
  end

  defp table?(_lines), do: false

  defp table([header, delimiter | rest]) do
    {rows, rest} =
      Enum.split_while(rest, &(is_binary(&1) and not blank?(&1) and not interrupts?(&1)))

    header = cells(header)
    columns = length(header)
    aligns = delimiter |> cells() |> Enum.map(&align/1)

    rows =
      Enum.map(
        rows,
        &(&1 |> cells() |> Enum.concat(List.duplicate("", columns)) |> Enum.take(columns))
      )

    {[{:table, aligns, header, rows}], rest}
  end

  # A row's cells, split at pipes that are not escaped.
  defp cells(line) do
    line = String.trim(line)

    line =
      if String.starts_with?(line, "|"), do: binary_part(line, 1, byte_size(line) - 1), else: line

    line =
      if String.ends_with?(line, "|") and not String.ends_with?(line, "\\|"),
        do: binary_part(line, 0, byte_size(line) - 1),
        else: line

    ~r/(?<!\\)\|/
    |> Regex.split(line)
    |> Enum.map(&(&1 |> String.replace("\\|", "|") |> String.trim()))
  end

  defp align(cell) do
    case {String.starts_with?(cell, ":"), String.ends_with?(cell, ":")} do
      {true, true} -> :center
      {true, false} -> :left
      {false, true} -> :right
      {false, false} -> nil
    end
  end

  # -- paragraphs ---------------------------------------------------------------

  defp paragraph([first | rest] = all) do
    {lines, level, rest} = take_paragraph(rest, [first])
    {definitions, text_lines} = lines |> Enum.map(&String.trim_leading/1) |> take_definitions([])
    text = text_lines |> Enum.join("\n") |> String.trim_trailing()

    cond do
      text == "" and level ->
        # Definitions alone make no heading: their underline is a line of its own.
        {definitions, Enum.drop(all, length(lines))}

      text == "" ->
        {definitions, rest}

      level ->
        {definitions ++ [{:heading, level, text}], rest}

      true ->
        {definitions ++ [{:paragraph, text}], rest}
    end
  end

  # A paragraph's lines, and the level of the setext heading they make when
  # a line of `=` or `-` follows them. A lazy line is only text.
  defp take_paragraph([], acc), do: {Enum.reverse(acc), nil, []}

  defp take_paragraph([{:lazy, line} | rest], acc), do: take_paragraph(rest, [line | acc])

  defp take_paragraph([line | rest] = lines, acc) do
    cond do
      blank?(line) -> {Enum.reverse(acc), nil, lines}
      Regex.match?(~r/^ {0,3}=+ *$/, line) -> {Enum.reverse(acc), 1, rest}
      Regex.match?(~r/^ {0,3}-+ *$/, line) -> {Enum.reverse(acc), 2, rest}
      table?(lines) or interrupts?(line) -> {Enum.reverse(acc), nil, lines}
      true -> take_paragraph(rest, [line | acc])
    end
  end

  # Link reference definitions (`[label]: url "title"`) open a paragraph. A
  # label has more than spaces, and only `<>` makes an empty URL.
  defp take_definitions([line | rest] = lines, acc) do
    with [_, label, angled | bare] <-
           Regex.run(
             ~r/^\[((?:[^\]\\]|\\.)+)\]: *(?:<([^<>\n]*)>|([^\s<>]+))(?: +(?:"[^"]*"|'[^']*'|\([^)]*\)))? *$/,
             line
           ),
         label when label != "" <- normalize(label) do
      take_definitions(rest, [{:definition, label, unescape(angled <> Enum.join(bare))} | acc])
    else
      _ -> {Enum.reverse(acc), lines}
    end
  end

  defp take_definitions([], acc), do: {Enum.reverse(acc), []}

  defp normalize(label), do: label |> String.split() |> Enum.join(" ") |> String.downcase()

  defp definitions(blocks) do
    Enum.flat_map(blocks, fn
      {:definition, label, url} ->
        [{label, url}]

      {:quote, inner} ->
        definitions(inner)

      {:list, _start, _tight, items} ->
        Enum.flat_map(items, fn {:item, _, inner} -> definitions(inner) end)

      _block ->
        []
    end)
  end

  defp resolve(blocks, refs) do
    Enum.flat_map(blocks, fn
      {:definition, _label, _url} ->
        []

      {:heading, level, text} ->
        [{:heading, level, inlines(text, refs)}]

      {:paragraph, text} ->
        [{:paragraph, inlines(text, refs)}]

      {:quote, inner} ->
        [{:quote, resolve(inner, refs)}]

      {:list, start, tight, items} ->
        [
          {:list, start, tight,
           Enum.map(items, fn {:item, task, inner} -> {:item, task, resolve(inner, refs)} end)}
        ]

      {:table, aligns, header, rows} ->
        cells = &Enum.map(&1, fn cell -> inlines(cell, refs) end)
        [{:table, aligns, cells.(header), Enum.map(rows, cells)}]

      block ->
        [block]
    end)
  end

  # -- inlines ------------------------------------------------------------------
  #
  # Text is scanned grapheme by grapheme into text, code, links and runs of
  # `*`, `_` and `~`, which then pair up into emphasis the CommonMark way.
  # A `[` or `![` stays text until a `]` with a destination or a defined
  # label after it makes a link or image of what lies between; once a link
  # forms, the `[`s before it can't open one, as links don't nest.

  defp inlines(text, refs) do
    g = text |> String.graphemes() |> List.to_tuple()

    # `tokens` holds `count` tokens, newest first. `brackets` holds the open
    # `[`s, numbered in order; those numbered below `inactive` can no longer
    # open a link. `unclosed` holds the lengths of backtick runs that have
    # no closing run left.
    state = %{
      tokens: [],
      count: 0,
      brackets: [],
      opened: 0,
      inactive: 0,
      unclosed: MapSet.new(),
      refs: refs
    }

    g |> scan(0, tuple_size(g), [], state) |> emphasis()
  end

  defp scan(_g, i, n, buf, state) when i >= n,
    do: state |> push_text(buf) |> Map.fetch!(:tokens) |> Enum.reverse()

  defp scan(g, i, n, buf, state) do
    case elem(g, i) do
      "\\" ->
        case at(g, i + 1, n) do
          "\n" -> scan(g, i + 2, n, [], push(state, buf, :line_break))
          char when char in @escapable -> scan(g, i + 2, n, [char | buf], state)
          _ -> scan(g, i + 1, n, ["\\" | buf], state)
        end

      "`" ->
        size = run(g, i, n, "`")

        case code_end(g, i + size, n, size, state) do
          {nil, state} ->
            scan(g, i + size, n, [String.duplicate("`", size) | buf], state)

          {j, state} ->
            code = {:code, code(slice(g, i + size, j))}
            scan(g, j + size, n, [], push(state, buf, code))
        end

      char when char in ["*", "_", "~"] ->
        size = run(g, i, n, char)

        if char == "~" and size > 2,
          do: scan(g, i + size, n, [String.duplicate("~", size) | buf], state),
          else: scan(g, i + size, n, [], push(state, buf, delimiter(g, i, n, char, size)))

      "!" ->
        if at(g, i + 1, n) == "[",
          do: scan(g, i + 2, n, [], open_bracket(state, buf, "![", i + 2)),
          else: scan(g, i + 1, n, ["!" | buf], state)

      "[" ->
        scan(g, i + 1, n, [], open_bracket(state, buf, "[", i + 1))

      "]" ->
        close_bracket(g, i, n, buf, state)

      "<" ->
        case angle(slice(g, i, angle_end(g, i + 1, n))) do
          {token, size} -> scan(g, i + size, n, [], push(state, buf, token))
          nil -> scan(g, i + 1, n, ["<" | buf], state)
        end

      "&" ->
        case entity(slice(g, i, min(i + 40, n))) do
          {char, size} -> scan(g, i + size, n, [char | buf], state)
          nil -> scan(g, i + 1, n, ["&" | buf], state)
        end

      "\n" ->
        # Two spaces before a line end break the line; a plain line end is a space.
        {spaces, buf} = Enum.split_while(buf, &(&1 == " "))

        if length(spaces) >= 2,
          do: scan(g, i + 1, n, [], push(state, buf, :line_break)),
          else: scan(g, i + 1, n, [" " | buf], state)

      char ->
        scan(g, i + 1, n, [char | buf], state)
    end
  end

  # Adds a token after the text gathered in `buf`.
  defp push(state, buf, token) do
    state = push_text(state, buf)
    %{state | tokens: [token | state.tokens], count: state.count + 1}
  end

  defp push_text(state, []), do: state

  defp push_text(state, buf),
    do: push(state, [], {:text, buf |> Enum.reverse() |> IO.iodata_to_binary()})

  defp at(g, i, n) when i >= 0 and i < n, do: elem(g, i)
  defp at(_g, _i, _n), do: nil

  defp slice(g, from, to) do
    if from >= to, do: "", else: Enum.map_join(from..(to - 1)//1, &elem(g, &1))
  end

  defp run(g, i, n, char) do
    if at(g, i, n) == char, do: 1 + run(g, i + 1, n, char), else: 0
  end

  # Where the run of `size` backticks that closes a code span starts. A
  # size with no closing run left is remembered, so no run looks again.
  defp code_end(g, i, n, size, state) do
    cond do
      MapSet.member?(state.unclosed, size) -> {nil, state}
      j = closing_backticks(g, i, n, size) -> {j, state}
      true -> {nil, %{state | unclosed: MapSet.put(state.unclosed, size)}}
    end
  end

  # The start of the next run of exactly `size` backticks.
  defp closing_backticks(_g, i, n, _size) when i >= n, do: nil

  defp closing_backticks(g, i, n, size) do
    if elem(g, i) == "`" do
      found = run(g, i, n, "`")
      if found == size, do: i, else: closing_backticks(g, i + found, n, size)
    else
      closing_backticks(g, i + 1, n, size)
    end
  end

  defp code(content) do
    content = String.replace(content, "\n", " ")

    if String.starts_with?(content, " ") and String.ends_with?(content, " ") and
         String.trim(content) != "",
       do: binary_part(content, 1, byte_size(content) - 2),
       else: content
  end

  # A run of `*`, `_` or `~`, with whether it can open and close emphasis
  # (CommonMark's flanking rules: `_` does not emphasize inside a word).
  defp delimiter(g, i, n, char, size) do
    before = at(g, i - 1, n) || " "
    next = at(g, i + size, n) || " "

    left? =
      not space?(next) and (not punctuation?(next) or space?(before) or punctuation?(before))

    right? =
      not space?(before) and (not punctuation?(before) or space?(next) or punctuation?(next))

    {open?, close?} =
      if char == "_",
        do:
          {left? and (not right? or punctuation?(before)),
           right? and (not left? or punctuation?(next))},
        else: {left?, right?}

    {:delimiter, char, size, size, open?, close?}
  end

  defp space?(char), do: String.trim(char) == ""
  defp punctuation?(char), do: Regex.match?(~r/^[\p{P}\p{S}]/u, char)

  # -- links --------------------------------------------------------------------

  defp open_bracket(state, buf, mark, start) do
    state = push(state, buf, {:text, mark})
    bracket = {mark == "![", start, state.count, state.opened}
    %{state | brackets: [bracket | state.brackets], opened: state.opened + 1}
  end

  # A `]` closes the latest open `[` or `![` into a link or image of the
  # tokens after it, when a destination or a defined label comes next.
  defp close_bracket(g, i, n, buf, %{brackets: [bracket | brackets], inactive: inactive} = state) do
    {image?, start, count, number} = bracket

    with true <- image? or number >= inactive,
         {:ok, url, next} <- target(g, i + 1, n, {start, i}, state.refs) do
      state = push_text(state, buf)
      {inner, [_mark | below]} = Enum.split(state.tokens, state.count - count)
      inner = inner |> Enum.reverse() |> emphasis()
      token = if image?, do: {:image, text(inner), url}, else: {:link, inner, url}
      inactive = if image?, do: inactive, else: number
      state = %{state | tokens: [token | below], count: count, inactive: inactive}
      scan(g, next, n, [], %{state | brackets: brackets})
    else
      _ -> scan(g, i + 1, n, ["]" | buf], %{state | brackets: brackets})
    end
  end

  defp close_bracket(g, i, n, buf, state), do: scan(g, i + 1, n, ["]" | buf], state)

  # What follows a `]`: `(url "title")`, or a reference: `[label]`, or `[]`
  # or nothing, which take the label from the bracketed `text`.
  defp target(g, i, n, text, refs) do
    with :error <- destination(g, i, n), do: reference(g, i, n, text, refs)
  end

  defp destination(g, i, n) do
    with "(" <- at(g, i, n),
         {:ok, url, i} <- url(g, skip_spaces(g, i + 1, n), n),
         {:ok, i} <- title(g, skip_spaces(g, i, n), n),
         i = skip_spaces(g, i, n),
         ")" <- at(g, i, n) do
      {:ok, unescape(url), i + 1}
    else
      _ -> :error
    end
  end

  defp skip_spaces(g, i, n) do
    if at(g, i, n) in [" ", "\n"], do: skip_spaces(g, i + 1, n), else: i
  end

  defp url(g, i, n) do
    if at(g, i, n) == "<" do
      case Regex.run(~r/^<([^<>\n]*)>/, slice(g, i, angle_end(g, i + 1, n))) do
        [whole, url] -> {:ok, url, i + String.length(whole)}
        nil -> :error
      end
    else
      bare_url(g, i, n, i, 0)
    end
  end

  # Up to a space or the `)` that closes the link; balanced parentheses
  # stay, nested at most 32 deep.
  defp bare_url(g, i, n, start, depth) do
    case at(g, i, n) do
      char when char in [nil, " ", "\n"] -> {:ok, slice(g, start, min(i, n)), i}
      "\\" -> bare_url(g, i + 2, n, start, depth)
      "(" when depth == 32 -> :error
      "(" -> bare_url(g, i + 1, n, start, depth + 1)
      ")" when depth == 0 -> {:ok, slice(g, start, i), i}
      ")" -> bare_url(g, i + 1, n, start, depth - 1)
      _ -> bare_url(g, i + 1, n, start, depth)
    end
  end

  defp title(g, i, n) do
    case at(g, i, n) do
      mark when mark in ["\"", "'", "("] ->
        close = if mark == "(", do: ")", else: mark

        case closing(g, i + 1, n, close) do
          nil -> :error
          j -> {:ok, j + 1}
        end

      _ ->
        {:ok, i}
    end
  end

  # The next unescaped `char`; a `(` title can't hold another `(`.
  defp closing(_g, i, n, _char) when i >= n, do: nil

  defp closing(g, i, n, char) do
    case elem(g, i) do
      "\\" -> closing(g, i + 2, n, char)
      ^char -> i
      "(" when char == ")" -> nil
      _ -> closing(g, i + 1, n, char)
    end
  end

  defp reference(g, i, n, text, refs) do
    {{from, to}, next} =
      case at(g, i, n) == "[" and closing(g, i + 1, n, "]") do
        j when is_integer(j) and j > i + 1 -> {{i + 1, j}, j + 1}
        j when is_integer(j) -> {text, j + 1}
        _ -> {text, i}
      end

    # A label is at most 999 characters long.
    with true <- to - from <= 999,
         {:ok, url} <- Map.fetch(refs, normalize(slice(g, from, to))) do
      {:ok, url, next}
    else
      _ -> :error
    end
  end

  # Where a `<...>` ends: just after its `>`, or at a `<` or line end.
  defp angle_end(g, i, n) do
    case at(g, i, n) do
      nil -> n
      ">" -> i + 1
      char when char in ["<", "\n"] -> i
      _char -> angle_end(g, i + 1, n)
    end
  end

  defp unescape(url), do: Regex.replace(~r/\\([[:punct:]])/, url, "\\1")

  # `<scheme:...>` and `<user@host>` links, and `<br>`.
  defp angle(text) do
    cond do
      match = Regex.run(~r/^<([A-Za-z][A-Za-z0-9+.\-]{1,31}:[^\s<>]*)>/, text) ->
        [whole, url] = match
        {{:link, [{:text, url}], url}, String.length(whole)}

      match = Regex.run(~r/^<([^\s<>@]+@[^\s<>@]+\.[^\s<>@]+)>/, text) ->
        [whole, email] = match
        {{:link, [{:text, email}], "mailto:" <> email}, String.length(whole)}

      match = Regex.run(~r/^<br\s*\/?>/i, text) ->
        {:line_break, String.length(hd(match))}

      true ->
        nil
    end
  end

  defp entity(text) do
    case Regex.run(
           ~r/^&(?:\#[xX]([0-9a-fA-F]{1,6})|\#([0-9]{1,7})|([A-Za-z][A-Za-z0-9]{1,31}));/,
           text
         ) do
      [whole, hex] -> {codepoint(String.to_integer(hex, 16)), String.length(whole)}
      [whole, "", decimal] -> {codepoint(String.to_integer(decimal)), String.length(whole)}
      [whole, "", "", name] -> if char = @entities[name], do: {char, String.length(whole)}
      nil -> nil
    end
  end

  defp codepoint(0), do: "�"

  defp codepoint(value) do
    <<value::utf8>>
  rescue
    ArgumentError -> "�"
  end

  # -- emphasis -----------------------------------------------------------------
  #
  # Tokens go onto a stack in order. A run that can close looks down the
  # stack for the nearest run of its character that can open, and the pair
  # wraps what lies between. `*` and `_` pairs take two characters from
  # each run (strong) when both have two, else one. A look that finds no
  # opener leaves a floor that later closers of its kind don't look below,
  # which keeps long texts linear.

  defp emphasis(tokens), do: emphasis(tokens, [], 0, %{})

  defp emphasis([], stack, _height, _floors), do: stack |> Enum.reverse() |> finish()

  defp emphasis(
         [{:delimiter, char, count, size, open?, true} = closer | rest],
         stack,
         height,
         floors
       ) do
    kind = {char, open?, rem(size, 3)}

    case opener(stack, height, Map.get(floors, kind, 0), closer, []) do
      nil ->
        closer = {:delimiter, char, count, size, open?, false}
        emphasis(rest, [closer | stack], height + 1, Map.put(floors, kind, height))

      {inside, opener, below, depth} ->
        used =
          if char == "~" or (elem(opener, 2) >= 2 and count >= 2), do: min(count, 2), else: 1

        pair =
          cond do
            char == "~" -> {:strikethrough, finish(inside)}
            used == 2 -> {:strong, finish(inside)}
            true -> {:emphasis, finish(inside)}
          end

        left = shrink(opener, used)
        floors = Map.new(floors, fn {kind, floor} -> {kind, min(floor, depth)} end)
        stack = [pair | left ++ below]
        emphasis(shrink(closer, used) ++ rest, stack, depth + length(left) + 1, floors)
    end
  end

  defp emphasis([token | rest], stack, height, floors),
    do: emphasis(rest, [token | stack], height + 1, floors)

  # The nearest opener for `closer` above `floor`: the tokens above it, the
  # opener, and the stack below it with its height.
  defp opener(_stack, height, floor, _closer, _inside) when height <= floor, do: nil

  defp opener([token | below], height, floor, closer, inside) do
    if pairs?(token, closer),
      do: {inside, token, below, height - 1},
      else: opener(below, height - 1, floor, closer, [token | inside])
  end

  defp pairs?(
         {:delimiter, char, opener_count, opener_size, true, opener_close?},
         {:delimiter, char, count, size, open?, _close?}
       ) do
    if char == "~",
      do: opener_count == count,
      # A run that can both open and close does not pair with one whose
      # length makes the sum a multiple of 3, unless both are.
      else:
        not ((opener_close? or open?) and rem(opener_size + size, 3) == 0 and
               not (rem(opener_size, 3) == 0 and rem(size, 3) == 0))
  end

  defp pairs?(_token, _closer), do: false

  defp shrink({:delimiter, _char, count, _size, _open?, _close?}, used) when count == used,
    do: []

  defp shrink({:delimiter, char, count, size, open?, close?}, used),
    do: [{:delimiter, char, count - used, size, open?, close?}]

  # Unpaired runs are text again; neighbouring text merges.
  defp finish(tokens) do
    tokens
    |> Enum.map(fn
      {:delimiter, char, count, _size, _open?, _close?} ->
        {:text, String.duplicate(char, count)}

      token ->
        token
    end)
    |> Enum.chunk_by(&match?({:text, _}, &1))
    |> Enum.flat_map(fn
      [{:text, _} | _] = texts -> [{:text, Enum.map_join(texts, &elem(&1, 1))}]
      tokens -> tokens
    end)
  end
end

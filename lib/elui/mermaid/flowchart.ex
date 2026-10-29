defmodule Elui.Mermaid.Flowchart do
  @moduledoc false

  # Parses a Mermaid flowchart (`flowchart` or `graph`) into nodes, edges
  # and subgraphs, for `Elui.Mermaid.Layout` to place.
  #
  # Nodes are `%{id, label, shape}`, the label lines of spans. Edges are
  # `%{from, to, label, line, head, tail, length}`: `line` is `:solid`,
  # `:thick`, `:dotted` or `:invisible`; `head` and `tail` are `nil`,
  # `:arrow`, `:cross` or `:circle`; `length` is the ranks it spans at
  # least (`-->` 1, `--->` 2). Subgraphs are `%{id, title}`; `parents`
  # maps a node or subgraph to the subgraph holding it.

  alias Elui.Mermaid.Label

  defstruct direction: :tb, nodes: %{}, order: [], edges: [], subgraphs: %{}, parents: %{}

  @type t :: %__MODULE__{}

  @directions %{
    "TB" => :tb,
    "TD" => :tb,
    "BT" => :bt,
    "LR" => :lr,
    "RL" => :rl,
    ">" => :lr,
    "<" => :rl,
    "^" => :bt,
    "V" => :tb
  }

  # Openers, longest first, each with its closers and the shape they make.
  @shapes [
    {"(((", [{")))", :double_circle}]},
    {"((", [{"))", :circle}]},
    {"([", [{"])", :stadium}]},
    {"(", [{")", :round}]},
    {"[[", [{"]]", :subroutine}]},
    {"[(", [{")]", :cylinder}]},
    {"[/", [{"/]", :lean_right}, {"\\]", :trapezoid}]},
    {"[\\", [{"\\]", :lean_left}, {"/]", :inv_trapezoid}]},
    {"[", [{"]", :rect}]},
    {"{{", [{"}}", :hexagon}]},
    {"{", [{"}", :rhombus}]},
    {">", [{"]", :asymmetric}]}
  ]

  # Shape names of the `A@{ shape: … }` syntax.
  @named_shapes %{
    "rect" => :rect,
    "rectangle" => :rect,
    "proc" => :rect,
    "process" => :rect,
    "rounded" => :round,
    "event" => :round,
    "stadium" => :stadium,
    "pill" => :stadium,
    "terminal" => :stadium,
    "subroutine" => :subroutine,
    "subproc" => :subroutine,
    "subprocess" => :subroutine,
    "fr-rect" => :subroutine,
    "framed-rectangle" => :subroutine,
    "cyl" => :cylinder,
    "cylinder" => :cylinder,
    "db" => :cylinder,
    "database" => :cylinder,
    "circle" => :circle,
    "circ" => :circle,
    "dbl-circ" => :double_circle,
    "double-circle" => :double_circle,
    "diam" => :rhombus,
    "diamond" => :rhombus,
    "decision" => :rhombus,
    "question" => :rhombus,
    "hex" => :hexagon,
    "hexagon" => :hexagon,
    "prepare" => :hexagon,
    "lean-r" => :lean_right,
    "lean-right" => :lean_right,
    "in-out" => :lean_right,
    "lean-l" => :lean_left,
    "lean-left" => :lean_left,
    "out-in" => :lean_left,
    "trap-b" => :trapezoid,
    "trapezoid" => :trapezoid,
    "trapezoid-bottom" => :trapezoid,
    "priority" => :trapezoid,
    "trap-t" => :inv_trapezoid,
    "inv-trapezoid" => :inv_trapezoid,
    "trapezoid-top" => :inv_trapezoid,
    "manual" => :inv_trapezoid
  }

  @keyword ~r/\A(subgraph|end|direction|classDef|class|style|linkStyle|click|accTitle|accDescr)(?=[\s;:{]|\z)/

  # A node id: letters, digits and some punctuation; a `-` or `.` only
  # where no link starts.
  @id ~r/\A(?:[\p{L}\p{N}_!?#$\/\\']|-(?![->.])|\.(?![-.]))+/u

  @doc """
  Parses what follows the `flowchart` or `graph` keyword; `line` is the
  keyword's line in the source, for error messages.
  """
  @spec parse(String.t(), pos_integer()) :: {:ok, t()} | {:error, String.t()}
  def parse(text, line \\ 1) do
    {direction, rest} = direction(text)

    state = %{
      source: text,
      line: line,
      nodes: %{},
      order: [],
      edges: [],
      open: [],
      closed: [],
      defined: MapSet.new(),
      count: 0
    }

    with {:ok, state} <- statements(rest, state) do
      {:ok, finish(state, direction)}
    end
  end

  defp direction(text) do
    case Regex.run(~r/\A[ \t]*(TB|TD|BT|RL|LR|[<>^v])(?=[\s;]|\z)/i, text) do
      [whole, direction] ->
        {@directions[String.upcase(direction)], binary_slice(text, byte_size(whole)..-1//1)}

      nil ->
        {:tb, text}
    end
  end

  # -- statements ---------------------------------------------------------------------------

  defp statements(rest, state) do
    rest = skip_separators(rest)

    cond do
      rest == "" ->
        {:ok, state}

      String.starts_with?(rest, "%%") ->
        statements(skip_line(rest), state)

      match = Regex.run(@keyword, rest) ->
        [word, _] = match
        keyword(word, drop(rest, word), state)

      true ->
        with {:ok, rest, state} <- chain(rest, state),
             {:ok, rest} <- statement_end(rest, state) do
          statements(rest, state)
        end
    end
  end

  defp keyword("subgraph", rest, state) do
    {header, rest} = take_statement(rest)
    {id, title} = subgraph_header(String.trim(header), state.count)
    subgraph = %{id: id, title: title, members: []}
    statements(rest, %{state | open: [subgraph | state.open], count: state.count + 1})
  end

  defp keyword("end", rest, state) do
    case state.open do
      [] -> error(state, rest, "`end` without a `subgraph`")
      _ -> statements(rest, close_subgraph(state))
    end
  end

  defp keyword("accDescr", rest, state) do
    case Regex.run(~r/\A\s*\{[^}]*\}/, rest) do
      [block] -> statements(drop(rest, block), state)
      nil -> statements(rest |> take_statement() |> elem(1), state)
    end
  end

  # Styling, links and accessibility text change nothing drawn here.
  defp keyword(_word, rest, state), do: statements(rest |> take_statement() |> elem(1), state)

  defp subgraph_header("", count), do: {"subgraph#{count}", []}

  defp subgraph_header(header, _count) do
    cond do
      match = Regex.run(~r/^"([^"]*)"$/, header) ->
        [_, title] = match
        {title, Label.parse(title)}

      match = Regex.run(~r/^([^\s\[]+)\s*\[(.*)\]$/, header) ->
        [_, id, title] = match
        {id, title |> String.trim() |> strip_quotes() |> Label.parse()}

      true ->
        {header, Label.parse(header)}
    end
  end

  defp close_subgraph(%{open: [subgraph | open]} = state) do
    state = %{state | open: open, closed: [subgraph | state.closed]}
    member(state, subgraph.id)
  end

  defp member(%{open: [subgraph | open]} = state, id),
    do: %{state | open: [%{subgraph | members: [id | subgraph.members]} | open]}

  defp member(state, _id), do: state

  defp statement_end(rest, state) do
    case skip_blank(rest) do
      "" -> {:ok, ""}
      "\n" <> _ = rest -> {:ok, rest}
      ";" <> _ = rest -> {:ok, rest}
      "%%" <> _ = rest -> {:ok, skip_line(rest)}
      other -> error(state, other, "unexpected #{inspect(snippet(other))}")
    end
  end

  # -- chains of nodes and links ------------------------------------------------------------

  defp chain(rest, state) do
    case group(rest, state, []) do
      {:ok, ids, rest, state} -> links(rest, ids, state)
      :none -> error(state, rest, "expected a node, got #{inspect(snippet(rest))}")
      {:error, _message} = error -> error
    end
  end

  defp links(rest, from, state) do
    case link(skip_blank(rest), state) do
      {:ok, link, rest} ->
        rest = skip_space(rest)

        case group(rest, state, []) do
          {:ok, to, rest, state} ->
            edges = for f <- from, t <- to, do: Map.merge(link, %{from: f, to: t})
            links(rest, to, %{state | edges: Enum.reverse(edges, state.edges)})

          :none ->
            error(state, rest, "expected a node after a link")

          {:error, _message} = error ->
            error
        end

      :none ->
        {:ok, rest, state}

      {:error, _message} = error ->
        error
    end
  end

  # Nodes joined by `&`.
  defp group(rest, state, acc) do
    case node(rest, state) do
      {:ok, id, rest, state} ->
        case skip_blank(rest) do
          "&" <> more ->
            case group(skip_space(more), state, [id | acc]) do
              :none -> error(state, more, "expected a node after `&`")
              result -> result
            end

          _ ->
            {:ok, Enum.reverse([id | acc]), rest, state}
        end

      other ->
        other
    end
  end

  defp node(rest, state) do
    case Regex.run(@id, rest) do
      [id] ->
        rest = drop(rest, id)

        with {:ok, rest, state} <- shape(id, rest, state) do
          rest = Regex.replace(~r/\A:::[\w-]+/, rest, "")
          {:ok, id, rest, state |> reference(id) |> member(id)}
        end

      nil ->
        :none
    end
  end

  defp reference(state, id) do
    if Map.has_key?(state.nodes, id) do
      state
    else
      node = %{id: id, label: Label.parse(id), shape: :rect}
      %{state | nodes: Map.put(state.nodes, id, node), order: [id | state.order]}
    end
  end

  defp define(state, id, label, shape) do
    state = reference(state, id)

    %{
      state
      | nodes: Map.update!(state.nodes, id, &%{&1 | label: label, shape: shape}),
        defined: MapSet.put(state.defined, id)
    }
  end

  defp shape(id, "@{" <> rest, state) do
    case Regex.run(~r/\A((?:"[^"]*"|[^"}])*)\}/, rest) do
      [whole, body] ->
        fields =
          ~r/([\w-]+)\s*:\s*("[^"]*"|[^,]*)/
          |> Regex.scan(body)
          |> Map.new(fn [_, key, value] -> {key, value |> String.trim() |> strip_quotes()} end)

        shape = Map.get(@named_shapes, Map.get(fields, "shape", "rect"), :rect)
        label = fields |> Map.get("label", id) |> Label.parse()
        {:ok, drop(rest, whole), define(state, id, label, shape)}

      nil ->
        error(state, rest, "unclosed `@{`")
    end
  end

  defp shape(id, rest, state) do
    case Enum.find(@shapes, fn {opener, _closers} -> String.starts_with?(rest, opener) end) do
      nil -> {:ok, rest, state}
      _found -> shape_from(id, rest, @shapes, state)
    end
  end

  # Tries each opener `rest` starts with, longest first, until one closes.
  defp shape_from(_id, rest, [], state),
    do: error(state, rest, "unclosed #{inspect(snippet(rest))}")

  defp shape_from(id, rest, [{opener, closers} | shapes], state) do
    with true <- String.starts_with?(rest, opener),
         {:ok, text, shape, after_shape} <- shape_text(drop(rest, opener), closers) do
      {:ok, after_shape, define(state, id, Label.parse(text), shape)}
    else
      _ -> shape_from(id, rest, shapes, state)
    end
  end

  defp shape_text(rest, closers) do
    body = skip_blank(rest)

    if String.starts_with?(body, "\"") do
      with {:ok, text, after_text} <- quoted(body),
           after_text = skip_blank(after_text),
           {closer, shape} <-
             Enum.find(closers, fn {closer, _shape} -> String.starts_with?(after_text, closer) end) do
        {:ok, text, shape, drop(after_text, closer)}
      else
        _ -> :error
      end
    else
      line = rest |> String.split("\n", parts: 2) |> hd()

      closers
      |> Enum.flat_map(fn {closer, shape} ->
        case :binary.match(line, closer) do
          {at, _length} -> [{at, closer, shape}]
          :nomatch -> []
        end
      end)
      |> Enum.min(fn -> nil end)
      |> case do
        nil ->
          :error

        {at, closer, shape} ->
          {:ok, binary_part(line, 0, at), shape,
           binary_slice(rest, (at + byte_size(closer))..-1//1)}
      end
    end
  end

  defp quoted("\"" <> rest) do
    case :binary.match(rest, "\"") do
      {at, 1} -> {:ok, binary_part(rest, 0, at), binary_slice(rest, (at + 1)..-1//1)}
      :nomatch -> :error
    end
  end

  # -- links --------------------------------------------------------------------------------

  defp link(rest, state) do
    cond do
      match = Regex.run(~r/\A~{3,}/, rest) ->
        [tildes] = match
        finish_link(drop(rest, tildes), :invisible, "", "", byte_size(tildes) - 2, nil, state)

      match = Regex.run(~r/\A([xo<]?)-?(\.+)-([xo>]?)/, rest) ->
        [whole, start, dots, finish] = match
        finish_link(drop(rest, whole), :dotted, start, finish, byte_size(dots), nil, state)

      match = Regex.run(~r/\A([xo<]?)(-{2,}|={2,})([xo>]?)/, rest) ->
        [whole, start, bars, finish] = match
        line = if String.starts_with?(bars, "="), do: :thick, else: :solid

        if finish == "" and byte_size(bars) == 2 do
          text_link(drop(rest, whole), line, start, state)
        else
          length = if finish == "", do: byte_size(bars) - 2, else: byte_size(bars) - 1
          finish_link(drop(rest, whole), line, start, finish, length, nil, state)
        end

      match = Regex.run(~r/\A([xo<]?)-\./, rest) ->
        [whole, start] = match
        text_link(drop(rest, whole), :dotted, start, state)

      true ->
        :none
    end
  end

  # `A -- text --> B`, `A == text ==> B`, `A -. text .-> B`.
  defp text_link(rest, line, start, state) do
    closing =
      case line do
        :solid -> ~r/(-{2,})([-xo>])/
        :thick -> ~r/(={2,})([=xo>])/
        :dotted -> ~r/(\.+)-([xo>]?)/
      end

    body = skip_blank(rest)

    {text, after_text} =
      if String.starts_with?(body, "\"") do
        case quoted(body) do
          {:ok, text, after_text} -> {text, after_text}
          :error -> {nil, body}
        end
      else
        line_text = body |> String.split("\n", parts: 2) |> hd()

        case Regex.run(closing, line_text, return: :index) do
          [{at, _length} | _] -> {binary_part(line_text, 0, at), binary_slice(body, at..-1//1)}
          nil -> {nil, body}
        end
      end

    with true <- is_binary(text),
         [whole, bars, finish] <- Regex.run(closing, skip_blank(after_text)),
         true <- String.starts_with?(skip_blank(after_text), whole) do
      {finish, length} =
        case {line, finish} do
          {:dotted, finish} -> {finish, byte_size(bars)}
          {_line, finish} when finish in ["-", "="] -> {"", byte_size(bars) - 1}
          {_line, finish} -> {finish, byte_size(bars) - 1}
        end

      finish_link(
        drop(skip_blank(after_text), whole),
        line,
        start,
        finish,
        length,
        String.trim(text),
        state
      )
    else
      _ -> error(state, rest, "a link's text has no end")
    end
  end

  defp finish_link(rest, line, start, finish, length, text, state) do
    {text, rest} =
      case skip_blank(rest) do
        "|" <> piped ->
          case Regex.run(~r/\A("[^"]*"|[^|\n]*)\|/, piped) do
            [whole, text] -> {String.trim(text), drop(piped, whole)}
            nil -> {:error, piped}
          end

        _ ->
          {text, rest}
      end

    if text == :error do
      error(state, rest, "a link's `|text|` has no closing `|`")
    else
      label = if text in [nil, ""], do: nil, else: text |> strip_quotes() |> Label.parse()

      {:ok,
       %{
         line: line,
         head: end_mark(finish),
         tail: end_mark(start),
         length: max(length, 1),
         label: label
       }, rest}
    end
  end

  defp end_mark(mark) when mark in [">", "<"], do: :arrow
  defp end_mark("x"), do: :cross
  defp end_mark("o"), do: :circle
  defp end_mark(_mark), do: nil

  # -- the result ---------------------------------------------------------------------------

  defp finish(state, direction) do
    state = Enum.reduce(state.open, state, fn _subgraph, state -> close_subgraph(state) end)

    # A node in two subgraphs stays in the one that closed first, as
    # Mermaid has it. Nothing holds itself or a subgraph around it. A
    # subgraph named like a node given a shape, or like a subgraph before
    # it, gets a name of its own, so links to the name reach the node.
    {subgraphs, parents, _claimed, _renamed} =
      state.closed
      |> Enum.reverse()
      |> Enum.reduce({%{}, %{}, MapSet.new(), %{}}, fn subgraph,
                                                       {subgraphs, parents, claimed, renamed} ->
        members = subgraph.members |> Enum.reverse() |> Enum.map(&Map.get(renamed, &1, &1))

        {subgraph, renamed} =
          if Map.has_key?(subgraphs, subgraph.id) or MapSet.member?(state.defined, subgraph.id) do
            id = "#{subgraph.id}~#{map_size(subgraphs)}"
            {%{subgraph | id: id}, Map.put(renamed, subgraph.id, id)}
          else
            {subgraph, renamed}
          end

        around = ancestors(subgraph.id, parents)

        members =
          members
          |> Enum.uniq()
          |> Enum.reject(&(&1 in claimed or &1 == subgraph.id or &1 in around))

        parents = Enum.reduce(members, parents, &Map.put(&2, &1, subgraph.id))
        subgraph = %{id: subgraph.id, title: subgraph.title, members: members}

        {Map.put(subgraphs, subgraph.id, subgraph), parents,
         MapSet.union(claimed, MapSet.new(members)), renamed}
      end)

    # A subgraph with nothing in it is drawn as a node.
    {empty, subgraphs} =
      Map.split_with(subgraphs, fn {_id, subgraph} -> subgraph.members == [] end)

    nodes =
      Enum.reduce(empty, state.nodes, fn {id, subgraph}, nodes ->
        Map.put(nodes, id, %{id: id, label: subgraph.title, shape: :rect})
      end)

    order = Enum.reverse(state.order) ++ (Map.keys(empty) -- state.order)

    # Links to a subgraph's id name the subgraph, not a node.
    {nodes, order} =
      {Map.drop(nodes, Map.keys(subgraphs)), Enum.reject(order, &Map.has_key?(subgraphs, &1))}

    %__MODULE__{
      direction: direction,
      nodes: nodes,
      order: order,
      edges: Enum.reverse(state.edges),
      subgraphs:
        Map.new(subgraphs, fn {id, subgraph} -> {id, Map.delete(subgraph, :members)} end),
      parents: parents
    }
  end

  defp ancestors(id, parents, seen \\ []) do
    case Map.get(parents, id) do
      nil ->
        []

      parent ->
        if parent in seen, do: [], else: [parent | ancestors(parent, parents, [id | seen])]
    end
  end

  # -- text helpers -------------------------------------------------------------------------

  defp strip_quotes(text) do
    case Regex.run(~r/\A"(.*)"\z/s, text) do
      [_, inner] -> inner
      nil -> text
    end
  end

  defp drop(text, prefix), do: binary_slice(text, byte_size(prefix)..-1//1)

  defp skip_blank(text), do: String.trim_leading(text, " ") |> trim_tabs()
  defp trim_tabs("\t" <> rest), do: skip_blank(rest)
  defp trim_tabs(text), do: text

  defp skip_space(text), do: String.trim_leading(text)

  defp skip_separators(text) do
    case String.trim_leading(text) do
      ";" <> rest -> skip_separators(rest)
      rest -> rest
    end
  end

  defp skip_line(text) do
    case String.split(text, "\n", parts: 2) do
      [_line, rest] -> rest
      [_line] -> ""
    end
  end

  # The text up to the end of the line or a `;` outside quotes.
  defp take_statement(text) do
    case Regex.run(~r/\A(?:"[^"\n]*"|[^;\n"])*/, text) do
      [statement] -> {statement, drop(text, statement)}
    end
  end

  defp snippet(text) do
    text = text |> String.split("\n", parts: 2) |> hd()
    if String.length(text) > 20, do: String.slice(text, 0, 20) <> "…", else: text
  end

  defp error(state, rest, message) do
    consumed = byte_size(state.source) - byte_size(rest)
    line = state.line + (state.source |> binary_part(0, max(consumed, 0)) |> count_lines())
    {:error, "line #{line}: #{message}"}
  end

  defp count_lines(text), do: length(:binary.matches(text, "\n"))
end

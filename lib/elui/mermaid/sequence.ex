defmodule Elui.Mermaid.Sequence do
  @moduledoc false

  # Parses and draws a Mermaid sequence diagram: participants side by
  # side with their lifelines down the page, messages as arrows between
  # lifelines with their text above, notes, activations as heavy
  # lifelines, and `loop`/`alt`/`opt`/`par`/`critical`/`break`/`rect`
  # blocks as frames around the messages in them.

  alias Elui.Mermaid.{Grid, Label}
  alias Elui.Text.Span

  defstruct participants: [], events: [], title: nil

  @type t :: %__MODULE__{}

  # Arrows, longest first: the text, its line, and its head and tail.
  @arrows [
    {"<<-->>", :dotted, :arrow, :arrow},
    {"<<->>", :solid, :arrow, :arrow},
    {"-->>", :dotted, :arrow, nil},
    {"->>", :solid, :arrow, nil},
    {"--x", :dotted, :cross, nil},
    {"-x", :solid, :cross, nil},
    {"--)", :dotted, :arrow, nil},
    {"-)", :solid, :arrow, nil},
    {"-->", :dotted, nil, nil},
    {"->", :solid, nil, nil}
  ]

  @message Regex.compile!(
             "^(.+?)\\s*(" <>
               Enum.map_join(@arrows, "|", fn {arrow, _line, _head, _tail} ->
                 Regex.escape(arrow)
               end) <>
               ")\\s*([+-]?)\\s*([^:]+?)\\s*(?::(.*))?$"
           )

  @blocks ~w(loop alt opt par critical break rect box)
  @dividers ~w(else and option)
  @ignored ~w(destroy links link properties details accTitle accTitle: accDescr accDescr:)

  @doc "Parses what follows `sequenceDiagram`; `line` is the keyword's line."
  @spec parse(String.t(), pos_integer()) :: {:ok, t()} | {:error, String.t()}
  def parse(text, line \\ 1) do
    state = %{participants: [], labels: %{}, events: [], title: nil, open: []}

    # `;` ends a statement as a line break does (`#59;` writes one).
    text
    |> String.split("\n")
    |> Enum.with_index(line)
    |> Enum.flat_map(fn {raw, n} ->
      if raw |> String.trim_leading() |> String.starts_with?("%%"),
        do: [],
        else: raw |> String.split(";") |> Enum.map(&{String.trim(&1), n})
    end)
    |> Enum.reduce_while({:ok, state}, fn {raw, n}, {:ok, state} ->
      case statement(raw, state) do
        {:ok, state} -> {:cont, {:ok, state}}
        {:error, message} -> {:halt, {:error, "line #{n}: #{message}"}}
      end
    end)
    |> case do
      {:ok, state} ->
        participants =
          state.participants
          |> Enum.reverse()
          |> Enum.map(fn id -> state.labels |> Map.fetch!(id) |> Map.put(:id, id) end)

        # Blocks left open close at the end.
        unclosed =
          state.open |> Enum.reject(&(&1 == :box)) |> Enum.map(fn _kind -> :block_end end)

        events = Enum.reverse(state.events) ++ unclosed
        {:ok, %__MODULE__{participants: participants, events: events, title: state.title}}

      error ->
        error
    end
  end

  defp statement("", state), do: {:ok, state}

  defp statement(line, state) do
    [word | rest] = String.split(line, ~r/\s+/, parts: 2)
    rest = List.first(rest, "")

    cond do
      word in ["participant", "actor"] ->
        declare(state, rest, String.to_atom(word))

      word == "create" ->
        statement(rest, state)

      word in @ignored ->
        {:ok, state}

      word == "autonumber" ->
        autonumber(state, rest)

      word in ["title", "title:"] ->
        {:ok, %{state | title: rest |> String.trim_leading(":") |> String.trim()}}

      word in ["activate", "deactivate"] ->
        id = String.trim(rest)
        {:ok, state |> declared(id) |> event({String.to_atom(word), id})}

      String.downcase(word) == "note" ->
        note(state, rest)

      word in @blocks ->
        kind = String.to_atom(word)
        state = %{state | open: [kind | state.open]}
        # A box groups participants; it draws nothing here.
        {:ok, if(kind == :box, do: state, else: event(state, {:block_start, kind, label(rest)}))}

      word in @dividers ->
        {:ok, event(state, {:block_divider, String.to_atom(word), label(rest)})}

      word == "end" ->
        case state.open do
          [] -> {:error, "`end` without a block"}
          [:box | open] -> {:ok, %{state | open: open}}
          [_kind | open] -> {:ok, event(%{state | open: open}, :block_end)}
        end

      match = Regex.run(@message, line) ->
        message(state, match)

      true ->
        {:error, "can't read #{inspect(line)}"}
    end
  end

  # `autonumber`, `autonumber off`, or a start and a step.
  defp autonumber(state, rest) do
    case String.split(rest) do
      [] -> {:ok, event(state, {:autonumber, {1, 1}})}
      ["off"] -> {:ok, event(state, {:autonumber, nil})}
      [start] -> numbers(state, start, "1")
      [start, step] -> numbers(state, start, step)
      _ -> {:error, "can't read `autonumber #{rest}`"}
    end
  end

  defp numbers(state, start, step) do
    case {Integer.parse(start), Integer.parse(step)} do
      {{start, ""}, {step, ""}} -> {:ok, event(state, {:autonumber, {start, step}})}
      _ -> {:error, "can't read `autonumber #{start} #{step}`"}
    end
  end

  defp declare(state, rest, kind) do
    {id, label} =
      case Regex.run(~r/^(.+?)\s+as\s+(.+)$/, rest) do
        [_, id, label] -> {id, label}
        nil -> {rest, rest}
      end

    id = id |> String.trim() |> strip_quotes()

    if id == "" do
      {:error, "a participant needs a name"}
    else
      state = declared(state, id)
      {:ok, %{state | labels: Map.put(state.labels, id, %{label: label(label), kind: kind})}}
    end
  end

  # A participant first named in a message or note is declared there.
  defp declared(state, id) do
    if Map.has_key?(state.labels, id) do
      state
    else
      %{
        state
        | participants: [id | state.participants],
          labels: Map.put(state.labels, id, %{label: label(id), kind: :participant})
      }
    end
  end

  defp note(state, rest) do
    case Regex.run(~r/^(left of|right of|over)\s+([^:]+?)\s*:\s*(.*)$/i, rest) do
      [_, place, actors, text] ->
        actors = actors |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.take(2)
        state = Enum.reduce(actors, state, &declared(&2, &1))
        place = place |> String.downcase() |> String.replace(" of", "") |> String.to_atom()
        {:ok, event(state, {:note, place, actors, label(text)})}

      nil ->
        {:error, "can't read the note #{inspect(rest)}"}
    end
  end

  defp message(state, [_whole, from, arrow, sign, to | text]) do
    {_arrow, line, head, tail} = List.keyfind(@arrows, arrow, 0)
    from = from |> String.trim() |> strip_quotes()
    to = to |> String.trim() |> strip_quotes()

    message = %{
      from: from,
      to: to,
      line: line,
      head: head,
      tail: tail,
      text: label(List.first(text, "")),
      activate: sign == "+",
      deactivate: sign == "-"
    }

    {:ok, state |> declared(from) |> declared(to) |> event({:message, message})}
  end

  defp event(state, event), do: %{state | events: [event | state.events]}

  defp label(text), do: text |> String.trim() |> strip_quotes() |> Label.parse()

  defp strip_quotes(text) do
    case Regex.run(~r/\A"(.*)"\z/s, text) do
      [_, inner] -> inner
      nil -> text
    end
  end

  # -- drawing ------------------------------------------------------------------------------

  @doc """
  Draws the diagram into a grid; an error when it would take more than
  `:max_cells`.
  """
  @spec draw(t(), Keyword.t()) :: {:ok, Grid.t()} | {:error, String.t()}
  def draw(%__MODULE__{participants: []}, opts),
    do: {:ok, Grid.new(ascii: Keyword.get(opts, :ascii, false))}

  def draw(%__MODULE__{} = diagram, opts) do
    widest = Keyword.get(opts, :max_label_width, 30)
    ascii = Keyword.get(opts, :ascii, false)
    index = diagram.participants |> Enum.map(& &1.id) |> Enum.with_index() |> Map.new()

    boxes =
      Enum.map(diagram.participants, fn participant ->
        lines = participant.label |> Label.wrap(widest) |> nonempty()
        width = Label.width(lines) + 4
        width = if rem(width, 2) == 0, do: width + 1, else: width
        %{kind: participant.kind, lines: lines, w: width}
      end)

    box_height = (boxes |> Enum.map(&length(&1.lines)) |> Enum.max()) + 2
    events = number(diagram.events, widest)
    {rows, last} = rows(events, box_height)
    columns = columns(boxes, events, index)

    # Notes and frames can reach left of the first box: all moves right.
    {least, _most} = span(rows, columns, index, frames(rows, columns, index))
    columns = Map.new(columns, fn {i, x} -> {i, x - min(least, 0)} end)
    frames = frames(rows, columns, index)
    {_least, most} = span(rows, columns, index, frames)

    if (most + 1) * (last + box_height + 1) > Keyword.get(opts, :max_cells, :infinity) do
      {:error, "the diagram is too large to draw"}
    else
      {:ok, draw(boxes, rows, columns, index, frames, {box_height, last}, ascii)}
    end
  end

  defp draw(boxes, rows, columns, index, frames, {box_height, last}, ascii) do
    bottom = last + 1

    grid =
      boxes
      |> Enum.with_index()
      |> Enum.reduce(Grid.new(ascii: ascii), fn {_box, i}, grid ->
        Grid.line(grid, [{columns[i], box_height - 1}, {columns[i], bottom}], role: :lifeline)
      end)

    # Heavy where a participant is active.
    grid =
      rows
      |> activations(index, last)
      |> Enum.reduce(grid, fn {i, top, end_row}, grid ->
        Grid.line(grid, [{columns[i], top}, {columns[i], end_row}],
          weight: :heavy,
          role: :lifeline
        )
      end)

    grid =
      boxes
      |> Enum.with_index()
      |> Enum.reduce(grid, fn {box, i}, grid ->
        grid
        |> participant(box, columns[i], 0, box_height)
        |> participant(box, columns[i], bottom, box_height)
      end)

    grid = draw_frames(grid, frames)
    Enum.reduce(rows, grid, &draw_event(&2, &1, columns, index, ascii))
  end

  # The leftmost and rightmost columns anything is drawn in.
  defp span(rows, columns, index, frames) do
    events =
      Enum.flat_map(rows, fn {event, _y} ->
        case extent(event, columns, index) do
          nil -> []
          {left, right} -> [left, right]
        end
      end)

    boxes = Enum.flat_map(columns, fn {_i, x} -> [x - 2, x + 2] end)
    framed = Enum.flat_map(frames, fn %{span: {left, right}} -> [left, right] end)
    Enum.min_max(events ++ boxes ++ framed)
  end

  defp nonempty([]), do: [[]]
  defp nonempty(lines), do: lines

  # Message text with `autonumber`'s numbers, wrapped, and note text wrapped.
  defp number(events, widest) do
    {events, _n} =
      Enum.map_reduce(events, nil, fn
        {:autonumber, numbers}, _numbers ->
          {{:autonumber, numbers}, numbers}

        {:message, message}, numbers ->
          text =
            case {numbers, message.text} do
              {nil, text} -> text
              {{n, _step}, [first | rest]} -> [[Span.raw("#{n}. ") | first] | rest]
              {{n, _step}, []} -> [[Span.raw("#{n}.")]]
            end

          numbers = with {n, step} <- numbers, do: {n + step, step}
          {{:message, %{message | text: Label.wrap(text, widest)}}, numbers}

        {:note, place, actors, text}, n ->
          {{:note, place, actors, Label.wrap(text, widest)}, n}

        event, n ->
          {event, n}
      end)

    events
  end

  # Each participant's column: boxes apart, then far enough apart for
  # the text between them, the shortest spans first.
  defp columns(boxes, events, index) do
    count = length(boxes)
    halves = Enum.map(boxes, fn box -> {div(box.w - 1, 2), box.w - 1 - div(box.w - 1, 2)} end)

    needs =
      Enum.flat_map(events, fn
        {:message, %{from: from, to: to, text: text}} ->
          {i, j} = {index[from], index[to]}
          width = Label.width(text)

          cond do
            i != j -> [{min(i, j), max(i, j), width + 4}]
            i + 1 < count -> [{i, i + 1, width + 6}]
            true -> []
          end

        {:note, place, actors, text} ->
          note_needs(place, Enum.map(actors, &index[&1]), Label.width(text) + 4, count)

        _event ->
          []
      end)

    gaps =
      halves
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [{_lo1, hi1}, {lo2, _hi2}] -> hi1 + lo2 + 3 end)

    gaps =
      needs
      |> Enum.sort_by(fn {i, j, _need} -> j - i end)
      |> Enum.reduce(gaps, fn {i, j, need}, gaps ->
        have = gaps |> Enum.slice(i, j - i) |> Enum.sum()
        if have >= need, do: gaps, else: List.update_at(gaps, j - 1, &(&1 + need - have))
      end)

    {margin, _hi} = hd(halves)

    gaps
    |> Enum.scan(margin, &(&1 + &2))
    |> then(&[margin | &1])
    |> Enum.with_index()
    |> Map.new(fn {x, i} -> {i, x} end)
  end

  defp note_needs(:right, [i | _], width, count),
    do: if(i + 1 < count, do: [{i, i + 1, width + 3}], else: [])

  defp note_needs(:left, [i | _], width, _count),
    do: if(i > 0, do: [{i - 1, i, width + 3}], else: [])

  defp note_needs(:over, [i], width, count) do
    left = if i > 0, do: [{i - 1, i, div(width, 2) + 2}], else: []
    right = if i + 1 < count, do: [{i, i + 1, width - div(width, 2) + 1}], else: []
    left ++ right
  end

  defp note_needs(:over, [i, j], width, _count) do
    if i == j, do: [], else: [{min(i, j), max(i, j), width - 5}]
  end

  # Each event with its first row; and the row after the last.
  defp rows(events, top) do
    Enum.map_reduce(events, top, fn event, y ->
      height =
        case event do
          {:message, %{from: same, to: same, text: text}} -> max(2, length(text))
          {:message, %{text: text}} -> length(text) + 1
          {:note, _place, _actors, text} -> length(text) + 2
          {:block_start, _kind, _text} -> 1
          {:block_divider, _kind, _text} -> 1
          :block_end -> 1
          _other -> 0
        end

      {{event, y}, y + height}
    end)
  end

  # The rows each participant is active, from `activate` or a `+`
  # message to `deactivate` or a `-` message.
  defp activations(rows, index, last) do
    {spans, open} =
      Enum.reduce(rows, {[], %{}}, fn
        {{:activate, id}, y}, {spans, open} ->
          {spans, Map.update(open, index[id], [y], &[y | &1])}

        {{:deactivate, id}, y}, {spans, open} ->
          close(spans, open, index[id], y - 1)

        {{:message, message}, y}, {spans, open} ->
          arrow = if message.from == message.to, do: y + 1, else: y + length(message.text)

          {spans, open} =
            if message.deactivate,
              do: close(spans, open, index[message.from], arrow),
              else: {spans, open}

          if message.activate,
            do: {spans, Map.update(open, index[message.to], [arrow], &[arrow | &1])},
            else: {spans, open}

        _row, acc ->
          acc
      end)

    Enum.reduce(open, spans, fn {i, starts}, spans ->
      Enum.map(starts, &{i, &1, last}) ++ spans
    end)
  end

  defp close(spans, open, i, y) do
    case Map.get(open, i, []) do
      [] -> {spans, open}
      [start | rest] -> {[{i, start, max(y, start)} | spans], Map.put(open, i, rest)}
    end
  end

  defp participant(grid, box, x, y, height) do
    left = x - div(box.w - 1, 2)
    grid = Grid.box(grid, left, y, box.w, height, role: :node, round: box.kind == :actor)
    first = y + 1 + div(height - 2 - length(box.lines), 2)

    box.lines
    |> Enum.with_index()
    |> Enum.reduce(grid, fn {spans, i}, grid ->
      width = spans |> Enum.map(&Span.width/1) |> Enum.sum()
      Grid.text(grid, {left + div(box.w - width, 2), first + i}, spans, :label)
    end)
  end

  # -- frames -------------------------------------------------------------------------------

  # Blocks as frames around what is in them, outer frames around inner
  # ones, each labelled in its top border and at each `else`.
  defp frames(rows, columns, index) do
    {frames, _stack} =
      Enum.reduce(rows, {[], []}, fn
        {{:block_start, kind, text}, y}, {frames, stack} ->
          {frames,
           [
             %{kind: kind, label: frame_label(kind, text), top: y, dividers: [], span: nil}
             | stack
           ]}

        {{:block_divider, _kind, text}, y}, {frames, [frame | stack]} ->
          {frames, [%{frame | dividers: [{text, y} | frame.dividers]} | stack]}

        {:block_end, y}, {frames, [frame | stack]} ->
          {left, right} = frame.span || all_columns(columns)

          wanted =
            [
              Label.width([frame.label]) + 3
              | Enum.map(frame.dividers, fn {text, _y} -> divider_width(text) + 3 end)
            ]
            |> Enum.max()

          frame = Map.merge(frame, %{bottom: y, span: {left, max(right, left + wanted)}})
          {outer_left, outer_right} = frame.span
          {[frame | frames], grow(stack, {outer_left - 1, outer_right + 1})}

        {event, _y}, {frames, stack} ->
          case extent(event, columns, index) do
            nil -> {frames, stack}
            {left, right} -> {frames, grow(stack, {left - 2, right + 2})}
          end
      end)

    frames
  end

  defp draw_frames(grid, frames) do
    Enum.reduce(frames, grid, fn frame, grid ->
      {left, right} = frame.span

      grid =
        grid
        |> Grid.box(left, frame.top, right - left + 1, frame.bottom - frame.top + 1,
          role: :cluster,
          over: [:lifeline]
        )
        |> Grid.text({left + 2, frame.top}, frame.label, :cluster_title)

      Enum.reduce(frame.dividers, grid, fn {text, y}, grid ->
        grid =
          Grid.line(grid, [{left, y}, {right, y}],
            weight: :dotted,
            role: :cluster,
            over: [:lifeline]
          )

        if text == [],
          do: grid,
          else: Grid.text(grid, {left + 2, y}, [Span.raw(" ") | bracketed(text)], :cluster_title)
      end)
    end)
  end

  # The innermost open frame takes in `span`.
  defp grow([], _span), do: []

  defp grow([frame | stack], {left, right}) do
    span =
      case frame.span do
        nil -> {left, right}
        {l, r} -> {min(l, left), max(r, right)}
      end

    [%{frame | span: span} | stack]
  end

  # A `rect` only colours what is in it; its frame has no title.
  defp frame_label(:rect, _text), do: []

  defp frame_label(kind, text) do
    keyword = Span.new(" #{kind} ", add_modifier: [:bold])
    if text == [], do: [keyword], else: [keyword | bracketed(text)]
  end

  defp bracketed(text) do
    spans = text |> Enum.intersperse([Span.raw(" ")]) |> Enum.concat()
    [Span.raw("[") | spans] ++ [Span.raw("] ")]
  end

  defp divider_width([]), do: 0
  defp divider_width(text), do: Label.width([bracketed(text)]) + 1

  defp all_columns(columns) do
    xs = Map.values(columns)
    {Enum.min(xs) - 2, Enum.max(xs) + 2}
  end

  # The columns an event's drawing takes.
  defp extent({:message, %{from: same, to: same, text: text}}, columns, index) do
    x = columns[index[same]]
    {x, x + 5 + Label.width(text)}
  end

  defp extent({:message, %{from: from, to: to}}, columns, index) do
    {a, b} = {columns[index[from]], columns[index[to]]}
    {min(a, b), max(a, b)}
  end

  defp extent({:note, _place, _actors, _text} = note, columns, index) do
    {left, width} = note_box(note, columns, index)
    {left, left + width - 1}
  end

  defp extent(_event, _columns, _index), do: nil

  defp note_box({:note, place, actors, text}, columns, index) do
    width = Label.width(text) + 4
    xs = Enum.map(actors, &columns[index[&1]])

    case {place, xs} do
      {:right, [x | _]} ->
        {x + 2, width}

      {:left, [x | _]} ->
        {x - 1 - width, width}

      {:over, [x]} ->
        {x - div(width, 2), width}

      {:over, [a, b]} ->
        {a, b} = {min(a, b), max(a, b)}
        span = b - a + 5
        if span >= width, do: {a - 2, span}, else: {div(a + b, 2) - div(width, 2), width}
    end
  end

  # -- events -------------------------------------------------------------------------------

  # A message to oneself loops out to the right and back.
  defp draw_event(grid, {{:message, %{from: same, to: same} = message}, y}, columns, index, ascii) do
    x = columns[index[same]]
    weight = weight(message.line)
    points = [{x, y}, {x + 3, y}, {x + 3, y + 1}, {x + 1, y + 1}]
    grid = Grid.line(grid, points, weight: weight, role: :edge, round: true)

    grid =
      if message.head,
        do: head(grid, message.head, {x + 1, y + 1}, :left, ascii),
        else: Grid.line(grid, [{x + 1, y + 1}, {x, y + 1}], weight: weight, role: :edge)

    message.text
    |> Enum.with_index()
    |> Enum.reduce(grid, fn {spans, i}, grid ->
      Grid.text(grid, {x + 5, y + i}, spans, :edge_label)
    end)
  end

  # Other messages cross the lifelines between, their text above them.
  defp draw_event(grid, {{:message, message}, y}, columns, index, ascii) do
    {from, to} = {columns[index[message.from]], columns[index[message.to]]}
    step = if to > from, do: 1, else: -1
    row = y + length(message.text)
    weight = weight(message.line)

    grid =
      Grid.line(grid, [{from + step, row}, {to - step, row}],
        weight: weight,
        role: :edge,
        over: [:lifeline]
      )

    grid =
      if message.tail,
        do: head(grid, message.tail, {from + step, row}, direction(-step), ascii),
        else: Grid.line(grid, [{from, row}, {from + step, row}], weight: weight, role: :edge)

    grid =
      if message.head,
        do: head(grid, message.head, {to - step, row}, direction(step), ascii),
        else: Grid.line(grid, [{to - step, row}, {to, row}], weight: weight, role: :edge)

    middle = div(from + to, 2)

    message.text
    |> Enum.with_index()
    |> Enum.reduce(grid, fn {spans, i}, grid ->
      width = spans |> Enum.map(&Span.width/1) |> Enum.sum()
      Grid.text(grid, {middle - div(width, 2), y + i}, spans, :edge_label)
    end)
  end

  # A note is a box over the lifelines it covers.
  defp draw_event(grid, {{:note, _place, _actors, text} = note, y}, columns, index, _ascii) do
    {left, width} = note_box(note, columns, index)
    height = length(text) + 2
    grid = Grid.box(grid, left, y, width, height, role: :note, over: [:lifeline])
    blank = [Span.raw(String.duplicate(" ", width - 2))]
    grid = Enum.reduce(1..(height - 2)//1, grid, &Grid.text(&2, {left + 1, y + &1}, blank, :note))

    text
    |> Enum.with_index()
    |> Enum.reduce(grid, fn {spans, i}, grid ->
      line_width = spans |> Enum.map(&Span.width/1) |> Enum.sum()
      Grid.text(grid, {left + div(width - line_width, 2), y + 1 + i}, spans, :note)
    end)
  end

  defp draw_event(grid, _row, _columns, _index, _ascii), do: grid

  defp head(grid, :arrow, point, direction, _ascii), do: Grid.arrow(grid, point, direction, :edge)

  defp head(grid, :cross, point, _direction, ascii),
    do: Grid.mark(grid, point, if(ascii, do: "x", else: "×"), :edge)

  defp direction(1), do: :right
  defp direction(-1), do: :left

  defp weight(:dotted), do: :dotted
  defp weight(_line), do: :light
end

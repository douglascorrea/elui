defmodule Elui.Widgets.DatePicker.State do
  @moduledoc """
  The cursor date, the reference day and the typed text of an
  `Elui.Widgets.DatePicker`.

  Arrows move the cursor a day (Left/Right) or a week (Up/Down),
  Page Up/Page Down a month. Typing goes into the text, and whenever the
  text reads as a date (`Elui.Widgets.DatePicker.parse/2`) the cursor
  jumps there; moving the cursor clears the text. Enter confirms the
  cursor's date, Delete answers that there is no date, Esc cancels.
  """

  alias Elui.Widgets.DatePicker

  defstruct cursor: nil, today: nil, text: ""

  @type t :: %__MODULE__{cursor: Date.t(), today: Date.t(), text: String.t()}

  @typedoc "What `handle_key/2` asks the app to do."
  @type action :: :continue | {:confirm, Date.t()} | :clear | :cancel | :noop

  @doc """
  Creates picker state. Options: `:date` (where the cursor starts;
  default the reference day) and `:today` (the reference day for words
  like `tomorrow`; default the local date).
  """
  @spec new(Keyword.t()) :: t()
  def new(opts \\ []) do
    today = Keyword.get_lazy(opts, :today, &local_today/0)
    %__MODULE__{cursor: Keyword.get(opts, :date) || today, today: today}
  end

  @doc "What the typed text says: `{:ok, date}`, `:error`, or `:empty` when nothing is typed."
  @spec parsed(t()) :: {:ok, Date.t()} | :error | :empty
  def parsed(%__MODULE__{} = state) do
    if String.trim(state.text) == "", do: :empty, else: DatePicker.parse(state.text, state.today)
  end

  @doc """
  Applies a keyboard event. Returns `{state, action}` where `action` is
  `:continue`, `{:confirm, date}`, `:clear` (Delete: no date), `:cancel`
  or `:noop`. Enter does nothing while the text is not a date.
  """
  @spec handle_key(t(), term()) :: {t(), action()}
  def handle_key(%__MODULE__{} = state, {:key, :esc, _mods}), do: {state, :cancel}
  def handle_key(%__MODULE__{} = state, {:key, :delete, _mods}), do: {state, :clear}

  def handle_key(%__MODULE__{} = state, {:key, :enter, _mods}) do
    case parsed(state) do
      :error -> {state, :noop}
      _ -> {state, {:confirm, state.cursor}}
    end
  end

  def handle_key(state, {:key, :left, _mods}), do: {move(state, day: -1), :continue}
  def handle_key(state, {:key, :right, _mods}), do: {move(state, day: 1), :continue}
  def handle_key(state, {:key, :up, _mods}), do: {move(state, week: -1), :continue}
  def handle_key(state, {:key, :down, _mods}), do: {move(state, week: 1), :continue}
  def handle_key(state, {:key, :page_up, _mods}), do: {move(state, month: -1), :continue}
  def handle_key(state, {:key, :page_down, _mods}), do: {move(state, month: 1), :continue}

  def handle_key(%__MODULE__{} = state, {:key, :backspace, _mods}) do
    {type(state, String.slice(state.text, 0, max(String.length(state.text) - 1, 0))), :continue}
  end

  def handle_key(%__MODULE__{} = state, {:key, :space, _mods}) do
    {type(state, state.text <> " "), :continue}
  end

  def handle_key(%__MODULE__{} = state, {:key, {:char, char}, mods})
      when is_binary(char) and is_list(mods) do
    if Enum.any?(mods, &(&1 in [:ctrl, :alt])) do
      {state, :noop}
    else
      {type(state, state.text <> char), :continue}
    end
  end

  def handle_key(state, _event), do: {state, :noop}

  defp move(state, shift), do: %{state | cursor: Date.shift(state.cursor, shift), text: ""}

  defp type(state, text) do
    state = %{state | text: text}

    case parsed(state) do
      {:ok, date} -> %{state | cursor: date}
      _ -> state
    end
  end

  defp local_today, do: :calendar.local_time() |> elem(0) |> Date.from_erl!()
end

defmodule Elui.Widgets.DatePicker do
  @moduledoc """
  A date picker: a month calendar (`Elui.Widgets.Calendar`) with a
  cursor, a line to type a date into, and a line that says which date
  Enter will give.

  Typed dates (`parse/2`): `2026-11-15`, `today`, `tomorrow`,
  `yesterday`, a weekday (`fri`, `friday`: the next one after today),
  `next week` (next Monday), `next month` (its first day), `+3d`, `-1w`,
  `2m`, `1y`, `in 3 days`, `nov 15` or `15 nov` (with an optional year;
  without one, the next such day), and a day of the month (`15`: the next
  15th).

  Draw it in a modal sized with `size/1`:

      picker = DatePicker.new(block: Block.bordered(title: "Due"))
      {w, h} = DatePicker.size(picker)
      Modal.render_stateful(frame, picker, state, horizontal: {:length, w}, vertical: {:length, h})

  and feed it keys with `Elui.Widgets.DatePicker.State.handle_key/2`.
  """

  alias Elui.Buffer
  alias Elui.Layout.Rect
  alias Elui.Style
  alias Elui.Widgets.{Block, Calendar}
  alias Elui.Widgets.DatePicker.State

  # A month's grid: 7 days of 3 columns; header, weekdays and up to 6
  # weeks; then the input and status lines.
  @grid_width 21
  @calendar_height 8
  @height @calendar_height + 2

  @weekdays ~w(Mon Tue Wed Thu Fri Sat Sun)
  @weekday_names %{
    "mon" => 1,
    "monday" => 1,
    "tue" => 2,
    "tuesday" => 2,
    "wed" => 3,
    "wednesday" => 3,
    "thu" => 4,
    "thursday" => 4,
    "fri" => 5,
    "friday" => 5,
    "sat" => 6,
    "saturday" => 6,
    "sun" => 7,
    "sunday" => 7
  }
  @months %{
    "jan" => 1,
    "january" => 1,
    "feb" => 2,
    "february" => 2,
    "mar" => 3,
    "march" => 3,
    "apr" => 4,
    "april" => 4,
    "may" => 5,
    "jun" => 6,
    "june" => 6,
    "jul" => 7,
    "july" => 7,
    "aug" => 8,
    "august" => 8,
    "sep" => 9,
    "sept" => 9,
    "september" => 9,
    "oct" => 10,
    "october" => 10,
    "nov" => 11,
    "november" => 11,
    "dec" => 12,
    "december" => 12
  }

  defstruct block: nil,
            style: %Style{},
            cursor_style: %Style{},
            today_style: %Style{},
            events: %{},
            header_style: %Style{},
            weekdays_style: %Style{},
            hint_style: %Style{},
            error_style: %Style{},
            prompt: "> ",
            hint: "fri, +3d, 2026-11-15"

  @type t :: %__MODULE__{}

  @doc """
  Creates a date picker.

  Options: `:block`, `:style`, `:cursor_style` (default reversed),
  `:today_style` (default bold and underlined), `:events` (a map of
  `%Date{}` to style, as for `Elui.Widgets.Calendar`), `:header_style`,
  `:weekdays_style`, `:hint_style` (the hint and the status line; default
  dim), `:error_style` (default red), `:prompt` (default `"> "`), and
  `:hint` (shown while nothing is typed).
  """
  @spec new(Keyword.t()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      block: Keyword.get(opts, :block),
      style: Style.to_style(Keyword.get(opts, :style)),
      cursor_style: Style.to_style(Keyword.get(opts, :cursor_style, add_modifier: [:reversed])),
      today_style:
        Style.to_style(Keyword.get(opts, :today_style, add_modifier: [:bold, :underlined])),
      events:
        opts |> Keyword.get(:events, %{}) |> Map.new(fn {d, s} -> {d, Style.to_style(s)} end),
      header_style: Style.to_style(Keyword.get(opts, :header_style)),
      weekdays_style: Style.to_style(Keyword.get(opts, :weekdays_style)),
      hint_style: Style.to_style(Keyword.get(opts, :hint_style, add_modifier: [:dim])),
      error_style: Style.to_style(Keyword.get(opts, :error_style, fg: :red)),
      prompt: Keyword.get(opts, :prompt, "> "),
      hint: Keyword.get(opts, :hint, "fri, +3d, 2026-11-15")
    }
  end

  @doc "The `{width, height}` the picker needs, its block included."
  @spec size(t()) :: {pos_integer(), pos_integer()}
  def size(%__MODULE__{block: nil}), do: {@grid_width, @height}

  def size(%__MODULE__{block: block}) do
    inner = Block.inner(block, Rect.new(0, 0, 1000, 1000))
    {@grid_width + 1000 - inner.width, @height + 1000 - inner.height}
  end

  @doc """
  Reads `text` as a date, relative to `today`: `{:ok, date}` or `:error`.
  See the module documentation for what it understands; case and extra
  spaces do not matter.
  """
  @spec parse(String.t(), Date.t()) :: {:ok, Date.t()} | :error
  def parse(text, %Date{} = today) when is_binary(text) do
    text
    |> String.downcase()
    |> String.split()
    |> Enum.join(" ")
    |> parse_words(today)
  end

  defp parse_words("", _today), do: :error
  defp parse_words(word, today) when word in ["today", "tod"], do: {:ok, today}

  defp parse_words(word, today) when word in ["tomorrow", "tom", "tmr"],
    do: {:ok, Date.add(today, 1)}

  defp parse_words(word, today) when word in ["yesterday", "yday"], do: {:ok, Date.add(today, -1)}
  defp parse_words("next week", today), do: {:ok, next_weekday(today, 1)}

  defp parse_words("next month", today),
    do: {:ok, today |> Date.beginning_of_month() |> Date.shift(month: 1)}

  defp parse_words("in " <> rest, today), do: relative("+" <> rest, today)

  defp parse_words(text, today) do
    cond do
      Map.has_key?(@weekday_names, text) -> {:ok, next_weekday(today, @weekday_names[text])}
      match = Regex.run(~r/^(\d{4})-(\d{1,2})-(\d{1,2})$/, text) -> iso(match)
      Regex.match?(~r/^\d{1,2}$/, text) -> day_of_month(String.to_integer(text), today)
      # `15 nov` looks like `15 days` until the month is recognised.
      true -> with :error <- month_day(String.split(text), today), do: relative(text, today)
    end
  end

  defp iso([_, y, m, d]) do
    case Date.new(String.to_integer(y), String.to_integer(m), String.to_integer(d)) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> :error
    end
  end

  @units %{
    "d" => :day,
    "day" => :day,
    "days" => :day,
    "w" => :week,
    "wk" => :week,
    "week" => :week,
    "weeks" => :week,
    "m" => :month,
    "mo" => :month,
    "month" => :month,
    "months" => :month,
    "y" => :year,
    "yr" => :year,
    "year" => :year,
    "years" => :year
  }

  defp relative(text, today) do
    with [_, sign, n, unit] <- Regex.run(~r/^([+-]?)(\d+) ?([a-z]+)$/, text),
         {:ok, unit} <- Map.fetch(@units, unit) do
      n = if sign == "-", do: -String.to_integer(n), else: String.to_integer(n)
      {:ok, Date.shift(today, [{unit, n}])}
    else
      _ -> :error
    end
  end

  # The next day-of-month `day`: this month's when it is still ahead (or
  # today), else next month's.
  defp day_of_month(day, today) do
    this_month = Date.new(today.year, today.month, day)
    next = today |> Date.beginning_of_month() |> Date.shift(month: 1)

    case this_month do
      {:ok, date} when date.day >= today.day -> {:ok, date}
      _ -> with {:error, _} <- Date.new(next.year, next.month, day), do: :error
    end
  end

  # `nov 15`, `15 nov`, either with a year after it.
  defp month_day(words, today) do
    case words do
      [a, b] ->
        month_day(a, b, nil, today)

      [a, b, year] ->
        if year =~ ~r/^\d{4}$/, do: month_day(a, b, String.to_integer(year), today), else: :error

      _ ->
        :error
    end
  end

  defp month_day(a, b, year, today) do
    {month, day} =
      cond do
        Map.has_key?(@months, a) -> {@months[a], b}
        Map.has_key?(@months, b) -> {@months[b], a}
        true -> {nil, nil}
      end

    with true <- month != nil and day =~ ~r/^\d{1,2}$/,
         {:ok, date} <- Date.new(year || today.year, month, String.to_integer(day)) do
      if year == nil and Date.compare(date, today) == :lt,
        do: date_or_error(Date.new(today.year + 1, month, date.day)),
        else: {:ok, date}
    else
      _ -> :error
    end
  end

  defp date_or_error({:ok, date}), do: {:ok, date}
  defp date_or_error(_), do: :error

  # The first `weekday` (1 = Monday) after `today`, never `today` itself.
  defp next_weekday(today, weekday) do
    case Integer.mod(weekday - Date.day_of_week(today), 7) do
      0 -> Date.add(today, 7)
      delta -> Date.add(today, delta)
    end
  end

  @doc false
  def render_into(%__MODULE__{} = picker, area, buffer, %State{} = state) do
    buffer = Buffer.set_style(buffer, area, picker.style)
    {inner, buffer} = Block.render_with_block(picker.block, area, buffer)

    if Rect.empty?(inner) do
      {buffer, state}
    else
      events =
        picker.events
        |> Map.update(state.today, picker.today_style, &Style.patch(&1, picker.today_style))
        |> Map.update(state.cursor, picker.cursor_style, &Style.patch(&1, picker.cursor_style))

      calendar =
        Calendar.monthly(state.cursor,
          events: events,
          default_style: picker.style,
          show_month_header: true,
          month_header_style: picker.header_style,
          show_weekdays_header: true,
          weekdays_header_style: picker.weekdays_style
        )

      grid =
        Rect.new(
          inner.x,
          inner.y,
          min(@grid_width, inner.width),
          min(@calendar_height, inner.height)
        )

      buffer = Elui.Widget.render(calendar, grid, buffer)

      buffer =
        buffer
        |> input_line(picker, state, inner, inner.y + @calendar_height)
        |> status_line(picker, state, inner, inner.y + @calendar_height + 1)

      {buffer, state}
    end
  end

  defp input_line(buffer, picker, state, inner, y) do
    if y < Rect.bottom(inner) do
      {buffer, x} =
        Buffer.set_stringn(buffer, inner.x, y, picker.prompt, inner.width, picker.style)

      room = Rect.right(inner) - x

      cond do
        room <= 0 ->
          buffer

        state.text == "" ->
          {buffer, _} = Buffer.set_stringn(buffer, x, y, " ", 1, picker.cursor_style)

          buffer
          |> Buffer.set_stringn(x + 1, y, picker.hint, room - 1, picker.hint_style)
          |> elem(0)

        true ->
          # Show the end of a text too long for the line, and leave a cell
          # for the cursor.
          keep = min(String.length(state.text), room - 1)
          text = if keep > 0, do: String.slice(state.text, -keep..-1//1), else: ""
          {buffer, cx} = Buffer.set_stringn(buffer, x, y, text, room, picker.style)

          if cx < Rect.right(inner),
            do: elem(Buffer.set_stringn(buffer, cx, y, " ", 1, picker.cursor_style), 0),
            else: buffer
      end
    else
      buffer
    end
  end

  defp status_line(buffer, picker, state, inner, y) do
    if y < Rect.bottom(inner) do
      {text, style} =
        case State.parsed(state) do
          :error -> {"not a date", picker.error_style}
          _ -> {describe(state.cursor, state.today), picker.hint_style}
        end

      buffer |> Buffer.set_stringn(inner.x, y, text, inner.width, style) |> elem(0)
    else
      buffer
    end
  end

  # "Fri 2026-11-20 +27d", "Sat 2026-10-24 today".
  defp describe(date, today) do
    weekday = Enum.at(@weekdays, Date.day_of_week(date) - 1)

    relative =
      case Date.diff(date, today) do
        0 -> "today"
        1 -> "tomorrow"
        n when n > 0 -> "+#{n}d"
        n -> "#{n}d"
      end

    "#{weekday} #{Date.to_iso8601(date)} #{relative}"
  end

  defimpl Elui.StatefulWidget do
    def render(picker, area, buffer, state) do
      Elui.Widgets.DatePicker.render_into(picker, area, buffer, state)
    end
  end
end

defmodule Elui.Widgets.DatePickerTest do
  use ExUnit.Case, async: true

  alias Elui.Backend.Test, as: TestBackend
  alias Elui.Buffer
  alias Elui.Frame
  alias Elui.Terminal
  alias Elui.Widgets.{Block, DatePicker}
  alias Elui.Widgets.DatePicker.State

  # A Saturday.
  @today ~D[2026-10-24]

  defp parse(text, today \\ @today), do: DatePicker.parse(text, today)

  describe "parse" do
    test "ISO dates, and nothing that is not a real day" do
      assert parse("2026-11-15") == {:ok, ~D[2026-11-15]}
      assert parse("2026-1-5") == {:ok, ~D[2026-01-05]}
      assert parse("2026-02-30") == :error
    end

    test "today, tomorrow, yesterday, in any case" do
      assert parse("today") == {:ok, @today}
      assert parse(" Tomorrow ") == {:ok, ~D[2026-10-25]}
      assert parse("tom") == {:ok, ~D[2026-10-25]}
      assert parse("yesterday") == {:ok, ~D[2026-10-23]}
    end

    test "a weekday is the next one after today, never today" do
      assert parse("fri") == {:ok, ~D[2026-10-30]}
      assert parse("monday") == {:ok, ~D[2026-10-26]}
      assert parse("sat") == {:ok, ~D[2026-10-31]}
    end

    test "next week is next Monday; next month is its first day" do
      assert parse("next week") == {:ok, ~D[2026-10-26]}
      assert parse("next   month") == {:ok, ~D[2026-11-01]}
    end

    test "relative offsets" do
      assert parse("+3d") == {:ok, ~D[2026-10-27]}
      assert parse("3 days") == {:ok, ~D[2026-10-27]}
      assert parse("in 3 days") == {:ok, ~D[2026-10-27]}
      assert parse("-1w") == {:ok, ~D[2026-10-17]}
      assert parse("+1 week") == {:ok, ~D[2026-10-31]}
      assert parse("2m") == {:ok, ~D[2026-12-24]}
      assert parse("1y") == {:ok, ~D[2027-10-24]}
      assert parse("+1m", ~D[2026-01-31]) == {:ok, ~D[2026-02-28]}
    end

    test "a month and a day, either way round, with an optional year; else the next one" do
      assert parse("nov 15") == {:ok, ~D[2026-11-15]}
      assert parse("15 November") == {:ok, ~D[2026-11-15]}
      assert parse("Nov 15 2027") == {:ok, ~D[2027-11-15]}
      assert parse("jan 5") == {:ok, ~D[2027-01-05]}
      assert parse("oct 24") == {:ok, @today}
      assert parse("nov 40") == :error
    end

    test "a day of the month is the next such day" do
      assert parse("24") == {:ok, @today}
      assert parse("31") == {:ok, ~D[2026-10-31]}
      assert parse("15") == {:ok, ~D[2026-11-15]}
      assert parse("31", ~D[2026-11-24]) == {:ok, ~D[2026-12-31]}
    end

    test "anything else is not a date" do
      for text <- ["", "  ", "soon", "+3x", "fri day", "2026-13-01", "nov", "15 16"] do
        assert parse(text) == :error, "expected #{inspect(text)} not to be a date"
      end
    end
  end

  describe "keys" do
    test "the cursor starts on the given date, else today" do
      assert State.new(today: @today).cursor == @today
      assert State.new(today: @today, date: ~D[2026-12-01]).cursor == ~D[2026-12-01]
    end

    test "arrows move a day or a week, Page Up/Down a month, and clear the text" do
      state = State.new(today: @today) |> type("fri")
      state = press(state, :right)
      assert state.cursor == ~D[2026-10-31] and state.text == ""
      assert press(state, :left).cursor == ~D[2026-10-30]
      assert press(state, :down).cursor == ~D[2026-11-07]
      assert press(state, :up).cursor == ~D[2026-10-24]
      assert press(state, :page_down).cursor == ~D[2026-11-30]
      assert press(state, :page_up).cursor == ~D[2026-09-30]
    end

    test "the cursor follows the text whenever it reads as a date" do
      state = State.new(today: @today) |> type("f")
      assert state.cursor == @today and State.parsed(state) == :error
      state = type(state, "ri")
      assert state.cursor == ~D[2026-10-30]
      state = press(state, :backspace)
      assert state.text == "fr" and state.cursor == ~D[2026-10-30]
    end

    test "Enter confirms the cursor's date, but not while the text is not a date" do
      state = State.new(today: @today)
      assert {_, {:confirm, @today}} = State.handle_key(state, {:key, :enter, []})

      state = type(state, "+3d")
      assert {_, {:confirm, ~D[2026-10-27]}} = State.handle_key(state, {:key, :enter, []})

      state = type(state, "x")
      assert {_, :noop} = State.handle_key(state, {:key, :enter, []})
    end

    test "Delete answers no date, Esc cancels, Ctrl and Alt characters are not text" do
      state = State.new(today: @today)
      assert {_, :clear} = State.handle_key(state, {:key, :delete, []})
      assert {_, :cancel} = State.handle_key(state, {:key, :esc, []})
      assert {^state, :noop} = State.handle_key(state, {:key, {:char, "d"}, [:ctrl]})
      assert {^state, :noop} = State.handle_key(state, {:key, {:char, "d"}, [:alt]})
    end
  end

  describe "rendering" do
    test "size includes the block" do
      assert DatePicker.size(DatePicker.new()) == {21, 10}
      assert DatePicker.size(DatePicker.new(block: Block.bordered())) == {23, 12}
    end

    test "the month, the weekdays, the hint, and which date Enter gives" do
      picker = DatePicker.new(block: Block.bordered(title: "Due"))
      {lines, buffer} = draw(picker, State.new(today: @today))

      assert Enum.at(lines, 0) =~ "Due"
      assert Enum.at(lines, 1) =~ "October 2026"
      assert Enum.at(lines, 2) =~ "Su Mo Tu We Th Fr Sa"
      assert Enum.at(lines, 9) =~ "> "
      assert Enum.at(lines, 9) =~ "fri, +3d"
      assert Enum.at(lines, 10) =~ "Sat 2026-10-24 today"

      # The 24th is on the row of the week of 18–24, in the Saturday column.
      {x, y} = cell_of(lines, "24")
      assert MapSet.member?(Buffer.get(buffer, x, y).style.add_modifier, :reversed)
      assert MapSet.member?(Buffer.get(buffer, x, y).style.add_modifier, :bold)
    end

    test "typing moves the calendar and says how far away the date is" do
      picker = DatePicker.new(block: Block.bordered())
      {lines, _} = draw(picker, State.new(today: @today) |> type("dec 25"))

      assert Enum.at(lines, 1) =~ "December 2026"
      assert Enum.at(lines, 9) =~ "> dec 25"
      assert Enum.at(lines, 10) =~ "Fri 2026-12-25 +62d"
    end

    test "text that is not a date says so in the error style" do
      picker = DatePicker.new()
      {lines, buffer} = draw(picker, State.new(today: @today) |> type("soon"))
      assert Enum.at(lines, 9) =~ "not a date"
      assert Buffer.get(buffer, 0, 9).style.fg == :red
    end
  end

  defp type(state, text) do
    text
    |> String.graphemes()
    |> Enum.reduce(state, fn
      " ", st -> elem(State.handle_key(st, {:key, :space, []}), 0)
      g, st -> elem(State.handle_key(st, {:key, {:char, g}, []}), 0)
    end)
  end

  defp press(state, key), do: elem(State.handle_key(state, {:key, key, []}), 0)

  defp draw(picker, state) do
    {width, height} = DatePicker.size(picker)
    terminal = Terminal.new(backend: TestBackend, backend_opts: [width: width, height: height])

    {terminal, _state} =
      Terminal.draw(terminal, &Frame.render_stateful_widget(&1, picker, Frame.area(&1), state))

    backend = Terminal.backend_state(terminal)
    {TestBackend.to_lines(backend), TestBackend.buffer(backend)}
  end

  # The column and row of a day number in the calendar grid.
  defp cell_of(lines, day) do
    lines
    |> Enum.with_index()
    |> Enum.drop(3)
    |> Enum.find_value(fn {line, y} ->
      case Regex.run(~r/(?<![0-9])#{day}(?![0-9])/u, line, return: :index) do
        [{byte, _}] -> {String.length(binary_part(line, 0, byte)), y}
        nil -> nil
      end
    end)
  end
end

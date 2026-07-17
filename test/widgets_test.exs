defmodule Elui.WidgetsTest do
  use ExUnit.Case, async: true

  alias Elui.Buffer
  alias Elui.Layout.Rect
  alias Elui.Widgets.{Block, Calendar, Clear, Gauge, LineGauge, Paragraph, Sparkline, Tabs}
  alias Elui.Widgets.List, as: UiList
  alias Elui.Widgets.Table
  alias Elui.Widgets.Table.Row

  defp render(widget, width, height) do
    area = Rect.new(0, 0, width, height)
    buffer = Elui.Widget.render(widget, area, Buffer.empty(area))
    Buffer.to_lines(buffer)
  end

  defp render_stateful(widget, width, height, state) do
    area = Rect.new(0, 0, width, height)
    {buffer, state} = Elui.StatefulWidget.render(widget, area, Buffer.empty(area), state)
    {Buffer.to_lines(buffer), state}
  end

  describe "Block" do
    test "draws all borders" do
      lines = render(Block.bordered(), 5, 3)

      assert lines == [
               "┌───┐",
               "│   │",
               "└───┘"
             ]
    end

    test "rounded borders with title" do
      lines = render(Block.bordered(title: "T", border_type: :rounded), 5, 3)

      assert lines == [
               "╭T──╮",
               "│   │",
               "╰───╯"
             ]
    end

    test "inner accounts for borders and padding" do
      block = Block.bordered(padding: 1)
      inner = Block.inner(block, Rect.new(0, 0, 10, 10))
      assert inner == Rect.new(2, 2, 6, 6)
    end

    test "borders and titles preserve an inherited background" do
      area = Rect.new(0, 0, 5, 3)

      buffer =
        area
        |> Buffer.empty()
        |> Buffer.set_style(area, bg: :white)

      block =
        Block.bordered(
          title: "T",
          border_style: [fg: :blue],
          title_style: [fg: :magenta]
        )

      rendered = Elui.Widget.render(block, area, buffer)
      corner = Buffer.get(rendered, 0, 0)
      title = Buffer.get(rendered, 1, 0)

      assert corner.symbol == "┌"
      assert corner.style.fg == :blue
      assert corner.style.bg == :white

      assert title.symbol == "T"
      assert title.style.fg == :magenta
      assert title.style.bg == :white
    end
  end

  describe "Paragraph" do
    test "renders text inside a block" do
      lines = render(Paragraph.new("Hi", block: Block.bordered()), 6, 3)

      assert lines == [
               "┌────┐",
               "│Hi  │",
               "└────┘"
             ]
    end

    test "wraps long words" do
      lines = render(Paragraph.new("aaa bbb ccc", wrap: [trim: true]), 4, 3)
      assert lines == ["aaa ", "bbb ", "ccc "]
    end

    test "center alignment" do
      lines = render(Paragraph.new("ab", alignment: :center), 6, 1)
      assert lines == ["  ab  "]
    end

    test "vertical scroll" do
      lines = render(Paragraph.new("one\ntwo\nthree", scroll: {1, 0}), 5, 2)
      assert lines == ["two  ", "three"]
    end
  end

  describe "List" do
    test "renders items and highlights selection" do
      list =
        UiList.new(["a", "b", "c"], highlight_symbol: "> ")

      state = UiList.State.new(selected: 1)
      {lines, _state} = render_stateful(list, 5, 3, state)

      assert lines == ["  a  ", "> b  ", "  c  "]
    end

    test "scrolls to keep selection visible" do
      list = UiList.new(~w(a b c d e))
      state = UiList.State.new(selected: 4)
      {lines, state} = render_stateful(list, 3, 2, state)

      assert state.offset == 3
      assert lines == ["d  ", "e  "]
    end

    test "selection navigation wraps" do
      state = UiList.State.new()
      state = UiList.State.select_next(state, 3)
      assert state.selected == 0
      state = UiList.State.select_previous(state, 3)
      assert state.selected == 2
    end
  end

  describe "Table" do
    test "renders header and rows in columns" do
      table =
        Table.new(
          [Row.new(["a", "1"]), Row.new(["b", "2"])],
          [{:length, 3}, {:length, 3}],
          header: Row.new(["X", "Y"])
        )

      lines = render(table, 8, 3)
      assert lines == ["X   Y   ", "a   1   ", "b   2   "]
    end

    test "row selection applies highlight symbol" do
      table =
        Table.new([Row.new(["a"]), Row.new(["b"])], [{:length, 3}], highlight_symbol: ">")

      {lines, _} = render_stateful(table, 5, 2, Table.State.new(selected: 1))
      assert lines == [" a   ", ">b   "]
    end
  end

  describe "Tabs" do
    test "renders titles with dividers" do
      lines = render(Tabs.new(["one", "two"], selected: 0), 12, 1)
      assert hd(lines) == " one │ two  "
    end
  end

  describe "Gauge" do
    test "renders label and fills cells" do
      lines = render(Gauge.new(0.5, label: "50%"), 10, 1)
      line = hd(lines)
      assert String.contains?(line, "50%")
      assert String.starts_with?(line, "██")
    end
  end

  describe "LineGauge" do
    test "renders default percentage label" do
      lines = render(LineGauge.new(0.5), 10, 1)
      assert String.starts_with?(hd(lines), "50% ")
    end
  end

  describe "Sparkline" do
    test "renders proportional bars" do
      lines = render(Sparkline.new([0, 4, 8], max: 8), 3, 1)
      assert lines == [" ▄█"]
    end
  end

  describe "Clear" do
    test "erases previous content" do
      area = Rect.new(0, 0, 3, 1)
      buffer = Buffer.set_string(Buffer.empty(area), 0, 0, "abc")
      buffer = Elui.Widget.render(Clear.new(), area, buffer)
      assert Buffer.to_lines(buffer) == ["   "]
    end
  end

  describe "Calendar" do
    test "renders the days of the month" do
      cal = Calendar.monthly(~D[2026-07-06], show_month_header: true, show_weekdays_header: true)
      lines = render(cal, 22, 8)

      assert Enum.at(lines, 0) =~ "July 2026"
      assert Enum.at(lines, 1) =~ "Su Mo Tu We Th Fr Sa"
      # July 1st 2026 is a Wednesday
      assert Enum.at(lines, 2) =~ "1  2  3  4"
    end
  end

  describe "Scrollbar" do
    test "positions the thumb" do
      scrollbar = Elui.Widgets.Scrollbar.new(:vertical_right)
      state = Elui.Widgets.Scrollbar.State.new(10, position: 0)
      {lines, _} = render_stateful(scrollbar, 1, 6, state)

      assert hd(lines) == "↑"
      assert List.last(lines) == "↓"
      assert "█" in lines
    end
  end

  describe "Example widgets" do
    test "hyperlink strips injected terminal controls from label and URL" do
      line =
        Elui.Examples.Widgets.Hyperlink.new(
          "Docs\e]0;owned\a",
          "https://example.test/\a?x=\e]0"
        )
        |> render(80, 1)
        |> hd()

      assert line =~ "\e]8;;https://example.test/?x=]0\aDocs]0;owned\e]8;;\a"
      refute line =~ "\e]0;"
      refute line =~ "https://example.test/\a?x"
    end
  end
end

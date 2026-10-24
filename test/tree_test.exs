defmodule Elui.Widgets.TreeTest do
  use ExUnit.Case, async: true

  alias Elui.Backend.Test, as: TestBackend
  alias Elui.Buffer
  alias Elui.Frame
  alias Elui.Layout.Rect
  alias Elui.Terminal
  alias Elui.Widgets.Tree
  alias Elui.Widgets.Tree.{Item, State}

  # inbox
  #   1 write the parser
  #     2 lexer
  #   3 pick a name
  # vibex
  #   4 release 0.8
  # notes
  defp items do
    [
      Item.new(:inbox, "inbox", [
        Item.new(1, "write the parser", [Item.new(2, "lexer")]),
        Item.new(3, "pick a name")
      ]),
      Item.new(:vibex, "vibex", [Item.new(4, "release 0.8")]),
      Item.new(:notes, "notes")
    ]
  end

  defp ids(rows), do: Enum.map(rows, fn {item, depth} -> {item.id, depth} end)

  describe "rows" do
    test "every item in order with its depth; collapsed items hide their descendants" do
      assert ids(State.rows(items(), State.new())) ==
               [{:inbox, 0}, {1, 1}, {2, 2}, {3, 1}, {:vibex, 0}, {4, 1}, {:notes, 0}]

      state = State.new(collapsed: [1, :vibex])

      assert ids(State.rows(items(), state)) == [
               {:inbox, 0},
               {1, 1},
               {3, 1},
               {:vibex, 0},
               {:notes, 0}
             ]
    end
  end

  describe "moving" do
    test "from nothing selects the first row; stops at both ends" do
      state = State.new()
      assert State.select_next(state, items()).selected == :inbox
      assert State.select_previous(state, items()).selected == :inbox

      state = State.select_last(state, items())
      assert state.selected == :notes
      assert State.select_next(state, items()).selected == :notes

      state = State.select_first(state, items())
      assert State.select_previous(state, items()).selected == :inbox
      assert State.select_by(state, items(), 4).selected == :vibex
      assert State.select_by(state, items(), 100).selected == :notes
    end

    test "moving skips the rows a collapsed item hides" do
      state = State.new(selected: 1, collapsed: [1])
      assert State.select_next(state, items()).selected == 3
    end

    test "Left folds an open item, then goes to its parent; Right unfolds, then goes to the first child" do
      state = State.new(selected: 1)
      state = State.collapse_or_select_parent(state, items())
      assert State.collapsed?(state, 1) and state.selected == 1
      state = State.collapse_or_select_parent(state, items())
      assert state.selected == :inbox

      leaf = State.collapse_or_select_parent(State.new(selected: 2), items())
      assert leaf.selected == 1
      top = State.new(selected: :notes)
      assert State.collapse_or_select_parent(top, items()).selected == :notes

      state = State.new(selected: :vibex, collapsed: [:vibex])
      state = State.expand_or_select_child(state, items())
      refute State.collapsed?(state, :vibex)
      assert state.selected == :vibex
      assert State.expand_or_select_child(state, items()).selected == 4
      assert State.expand_or_select_child(State.new(selected: 3), items()).selected == 3
    end

    test "toggle, collapse_all and expand_all" do
      state = State.toggle(State.new(), :inbox)
      assert State.collapsed?(state, :inbox)
      refute State.collapsed?(State.toggle(state, :inbox), :inbox)

      state = State.collapse_all(State.new(), items())
      assert MapSet.equal?(state.collapsed, MapSet.new([:inbox, 1, :vibex]))
      assert State.expand_all(state).collapsed == MapSet.new()
    end

    test "parent and selected_item" do
      assert State.parent(items(), 2) == 1
      assert State.parent(items(), :inbox) == nil
      assert State.parent(items(), :missing) == nil
      assert State.selected_item(State.new(selected: 4), items()).label |> Elui.Text.width() == 11
    end
  end

  describe "keeping the selection when the tree changes" do
    test "a removed item gives way to the row now at its index" do
      state = State.sync(State.new(selected: 3), items())
      assert state.index == 3

      without_3 =
        List.update_at(items(), 0, fn inbox ->
          %{inbox | children: Enum.take(inbox.children, 1)}
        end)

      assert State.sync(state, without_3).selected == :vibex
    end

    test "an item folded out of sight gives way to its nearest visible ancestor" do
      state = State.new(selected: 2, collapsed: [:inbox])
      assert State.sync(state, items()).selected == :inbox

      state = State.new(selected: 2, collapsed: [1])
      assert State.sync(state, items()).selected == 1
    end

    test "an empty tree selects nothing; nil stays nil" do
      assert State.sync(State.new(selected: 1), []).selected == nil
      assert State.sync(State.new(), items()).selected == nil
    end
  end

  test "prune keeps the matching items and their ancestors" do
    pruned = Tree.prune(items(), &(&1.id in [2, :notes]))
    assert ids(State.rows(pruned, State.new())) == [{:inbox, 0}, {1, 1}, {2, 2}, {:notes, 0}]
    assert Tree.prune(items(), fn _ -> false end) == []
  end

  describe "rendering" do
    test "indents by depth, marks open, folded and leaf items" do
      tree = Tree.new(items())
      lines = render(tree, State.new(collapsed: [:vibex]), 24, 7)

      assert lines == [
               "▾ inbox                 ",
               "  ▾ write the parser    ",
               "      lexer             ",
               "    pick a name         ",
               "▸ vibex                 ",
               "  notes                 ",
               "                        "
             ]
    end

    test "the selected row takes the highlight style and symbol" do
      tree = Tree.new(items(), highlight_style: [bg: :blue], highlight_symbol: "> ", indent: 1)
      {lines, buffer, _state} = draw(tree, State.new(selected: 3), 20, 7)

      assert Enum.at(lines, 3) == ">    pick a name    "
      assert Enum.at(lines, 0) == "  ▾ inbox           "
      assert Buffer.get(buffer, 19, 3).style.bg == :blue
      assert Buffer.get(buffer, 19, 2).style.bg != :blue
    end

    test "custom symbols and a stateless render" do
      tree = Tree.new(items(), symbols: [expanded: "- ", collapsed: "+ ", leaf: "· "], indent: 0)
      lines = render_stateless(tree, 12, 3)
      assert lines == ["- inbox     ", "- write the ", "· lexer     "]
    end

    test "wrap: a long label wraps under itself" do
      items = [Item.new(:p, "project", [Item.new(1, "renew the passport before the trip")])]
      lines = render(Tree.new(items, wrap: true), State.new(), 20, 4)

      assert lines == [
               "▾ project           ",
               "    renew the       ",
               "    passport before ",
               "    the trip        "
             ]

      # Without wrap it is cut at the edge.
      assert render(Tree.new(items), State.new(), 20, 2) |> List.last() == "    renew the passpo"
    end

    test "scrolls just enough to keep the selection in view" do
      tree = Tree.new(items())
      {lines, _buffer, state} = draw(tree, State.new(selected: :notes), 20, 3)
      assert state.offset == 4
      assert Enum.map(lines, &String.trim/1) == ["▾ vibex", "release 0.8", "notes"]

      # Moving up inside the view keeps the offset.
      {_lines, _buffer, state} = draw(tree, State.select_previous(state, items()), 20, 3)
      assert state.offset == 4

      {_lines, _buffer, state} = draw(tree, State.select(state, 3), 20, 3)
      assert state.offset == 3
    end
  end

  describe "hit and label_area" do
    test "the fold marker toggles, the rest of the row selects" do
      tree = Tree.new(items())
      area = Rect.new(0, 0, 20, 7)
      {_lines, _buffer, state} = draw(tree, State.new(), 20, 7)

      assert Tree.hit(tree, area, state, {0, 0}) == {:toggle, :inbox}
      assert Tree.hit(tree, area, state, {5, 0}) == {:row, :inbox}
      assert Tree.hit(tree, area, state, {2, 1}) == {:toggle, 1}
      # A leaf's marker column is just part of its row.
      assert Tree.hit(tree, area, state, {4, 2}) == {:row, 2}
      assert Tree.hit(tree, area, state, {1, 6}) == {:row, :notes}
      assert Tree.hit(tree, area, State.new(collapsed: [:inbox, :vibex]), {1, 3}) == nil
    end

    test "label_area is where an inline editor goes" do
      tree = Tree.new(items())
      area = Rect.new(0, 0, 20, 7)
      assert Tree.label_area(tree, area, State.new(), 2) == Rect.new(6, 2, 14, 1)
      assert Tree.label_area(tree, area, State.new(collapsed: [:inbox]), 2) == nil
    end
  end

  defp render(tree, state, width, height) do
    {lines, _buffer, _state} = draw(tree, state, width, height)
    lines
  end

  defp draw(tree, state, width, height) do
    terminal = Terminal.new(backend: TestBackend, backend_opts: [width: width, height: height])

    {terminal, state} =
      Terminal.draw(terminal, fn frame ->
        Frame.render_stateful_widget(frame, tree, Frame.area(frame), state)
      end)

    backend = Terminal.backend_state(terminal)
    {TestBackend.to_lines(backend), TestBackend.buffer(backend), state}
  end

  defp render_stateless(tree, width, height) do
    terminal = Terminal.new(backend: TestBackend, backend_opts: [width: width, height: height])

    {terminal, _} =
      Terminal.draw(terminal, fn frame ->
        {Frame.render_widget(frame, tree, Frame.area(frame)), nil}
      end)

    terminal |> Terminal.backend_state() |> TestBackend.to_lines()
  end
end

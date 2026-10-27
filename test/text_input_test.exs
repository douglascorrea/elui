defmodule Elui.Widgets.TextInputTest do
  use ExUnit.Case, async: true

  alias Elui.Backend.Test, as: TestBackend
  alias Elui.{Buffer, Frame, Terminal}
  alias Elui.Layout.Rect
  alias Elui.Widgets.TextInput
  alias Elui.Widgets.TextInput.State

  defp keys(state, keys) do
    Enum.reduce(keys, state, fn key, state ->
      {state, _action} = State.handle_key(state, event(key))
      state
    end)
  end

  defp event({key, mods}), do: {:key, key(key), mods}
  defp event(key), do: {:key, key(key), []}

  defp key(key) when is_atom(key), do: key
  defp key(char), do: {:char, char}

  defp at(text, cursor), do: State.new(text: text, cursor: cursor)

  describe "typing and moving" do
    test "inserts at the cursor, by grapheme" do
      state = State.new(text: "héllo", cursor: 2) |> keys(["x", :space, "👍🏽"])
      assert {state.text, state.cursor} == {"héx 👍🏽llo", 5}
      assert State.new(text: "日本").cursor == 2
    end

    test "moves by grapheme, by word and to either end" do
      assert keys(at("ab cd  ef", 0), [:right, :right]).cursor == 2
      assert keys(at("ab cd  ef", 9), [{:left, [:alt]}]).cursor == 7
      assert keys(at("ab cd  ef", 9), [{"b", [:alt]}, {"b", [:alt]}]).cursor == 3
      assert keys(at("ab cd  ef", 0), [{:right, [:ctrl]}, {"f", [:alt]}]).cursor == 5
      assert keys(at("ab", 1), [{"e", [:ctrl]}]).cursor == 2
      assert keys(at("ab", 1), [{"a", [:ctrl]}]).cursor == 0
      assert keys(at("ab", 1), [:end, {"b", [:ctrl]}]).cursor == 1
      assert keys(at("ab", 1), [:home, {"f", [:ctrl]}]).cursor == 1
    end

    test "stops at the ends without changing anything" do
      assert State.handle_key(at("ab", 0), event(:left)) == {at("ab", 0), :noop}
      assert State.handle_key(at("ab", 2), event(:right)) == {at("ab", 2), :noop}
      assert State.handle_key(at("ab", 0), event(:backspace)) == {at("ab", 0), :noop}
      assert State.handle_key(at("ab", 2), event(:delete)) == {at("ab", 2), :noop}
    end
  end

  describe "deleting" do
    test "a grapheme either side" do
      assert keys(at("a👍🏽b", 2), [:backspace]) == at("ab", 1)
      assert keys(at("a👍🏽b", 1), [:delete]) == at("ab", 1)
      assert keys(at("abc", 1), [{"h", [:ctrl]}]) == at("bc", 0)
      assert keys(at("abc", 1), [{"d", [:ctrl]}]) == at("ac", 1)
    end

    test "a word either side, or to either end" do
      assert keys(at("fix the  login", 14), [{"w", [:ctrl]}]) == at("fix the  ", 9)
      assert keys(at("fix the  login", 9), [{:backspace, [:alt]}]) == at("fix login", 4)
      assert keys(at("fix the login", 3), [{"d", [:alt]}]) == at("fix login", 3)
      assert keys(at("fix the login", 4), [{"u", [:ctrl]}]) == at("the login", 0)
      assert keys(at("fix the login", 3), [{"k", [:ctrl]}]) == at("fix", 3)
    end
  end

  test "Enter submits the text, Esc cancels, other control keys do nothing" do
    assert State.handle_key(at("a", 1), event(:enter)) == {at("a", 1), {:submit, "a"}}
    assert State.handle_key(at("a", 1), event(:esc)) == {at("a", 1), :cancel}
    assert State.handle_key(at("a", 1), event({"z", [:ctrl]})) == {at("a", 1), :noop}
    assert State.handle_key(at("a", 1), event({"z", [:alt]})) == {at("a", 1), :noop}
    assert State.handle_key(at("a", 1), event(:tab)) == {at("a", 1), :noop}
    assert State.handle_key(at("a", 1), event({"a", [:shift]})) == {at("aa", 2), :continue}
  end

  describe "drawing" do
    test "shows the prompt, the text and the cursor cell" do
      {lines, buffer, _} = draw(TextInput.new(prompt: "> "), at("ab", 1), 10)
      assert lines == ["> ab      "]
      assert reversed?(buffer, 3, 0)
      refute reversed?(buffer, 2, 0)

      {_, buffer, _} = draw(TextInput.new(), at("ab", 2), 10)
      assert reversed?(buffer, 2, 0)
    end

    test "shows the placeholder while empty" do
      {lines, buffer, _} =
        draw(TextInput.new(prompt: "> ", placeholder: "new todo"), State.new(), 10)

      assert lines == [">  new tod"]
      assert reversed?(buffer, 2, 0)
      assert MapSet.member?(Buffer.get(buffer, 3, 0).style.add_modifier, :dim)
    end

    test "scrolls a long text to keep the cursor in view, and only as far as needed" do
      input = TextInput.new(prompt: "> ")
      {lines, _, state} = draw(input, State.new(text: "write the parser"), 10)
      assert lines == [">  parser "]
      assert state.offset == 9

      {lines, _, state} = draw(input, keys(state, [:left, :left]), 10)
      assert lines == [">  parser "]

      {lines, _, state} = draw(input, keys(state, [:home]), 10)
      assert lines == ["> write th"]
      assert state.offset == 0

      {lines, _, state} = draw(input, keys(state, [:end, {"w", [:ctrl]}]), 10)
      assert lines == ["> te the  "]
      assert state.offset == 3

      {lines, _, _} = draw(input, keys(state, [{"u", [:ctrl]}, "a"]), 10)
      assert lines == ["> a       "]
    end

    test "never splits a wide character" do
      {_, buffer, state} = draw(TextInput.new(), State.new(text: "日本語の文"), 6)
      assert state.offset == 3
      assert Enum.map([0, 2], &Buffer.get(buffer, &1, 0).symbol) == ["の", "文"]
      assert reversed?(buffer, 4, 0)

      area = %Rect{x: 0, y: 0, width: 6, height: 1}
      assert TextInput.cursor_position(TextInput.new(), area, state) == {4, 0}
    end

    test "gives the cursor's cell for the terminal cursor" do
      area = %Rect{x: 3, y: 2, width: 10, height: 1}
      assert TextInput.cursor_position(TextInput.new(prompt: "> "), area, at("abc", 1)) == {6, 2}

      assert TextInput.cursor_position(
               TextInput.new(prompt: "> "),
               %{area | height: 0},
               at("abc", 1)
             ) == nil
    end
  end

  defp reversed?(buffer, x, y),
    do: MapSet.member?(Buffer.get(buffer, x, y).style.add_modifier, :reversed)

  defp draw(input, state, width) do
    terminal = Terminal.new(backend: TestBackend, backend_opts: [width: width, height: 1])

    {terminal, state} =
      Terminal.draw(terminal, &Frame.render_stateful_widget(&1, input, Frame.area(&1), state))

    backend = Terminal.backend_state(terminal)
    {TestBackend.to_lines(backend), TestBackend.buffer(backend), state}
  end
end

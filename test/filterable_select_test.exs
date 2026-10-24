defmodule Elui.Widgets.FilterableSelectTest do
  use ExUnit.Case, async: true

  alias Elui.Backend.Test, as: TestBackend
  alias Elui.Buffer
  alias Elui.Terminal
  alias Elui.Widgets.{Block, FilterableSelect}
  alias Elui.Widgets.FilterableSelect.State

  test "filters labels and confirms the selected value" do
    state =
      State.new([
        %{label: "#1 hello", value: 1},
        %{label: "#2 world", value: 2},
        %{label: "#3 help", value: 3}
      ])

    {state, :continue} = State.handle_key(state, {:key, {:char, "h"}, []})
    {state, :continue} = State.handle_key(state, {:key, {:char, "e"}, []})
    assert Enum.map(State.filtered(state), & &1.value) == [1, 3]

    {state, :continue} = State.handle_key(state, {:key, :down, []})
    assert State.selected_value(state) == 3
    {_state, {:confirm, 3}} = State.handle_key(state, {:key, :enter, []})
  end

  test "limits filtered results and cancels on Esc" do
    items = for n <- 1..10, do: "item-#{n}"
    state = State.new(items, limit: 3, filter: "item")
    assert length(State.filtered(state)) == 3
    {_state, :cancel} = State.handle_key(state, {:key, :esc, []})
  end

  test "renders matching labels inside a modal" do
    state = State.new(["America/New_York", "America/Sao_Paulo", "Europe/Paris"], filter: "Sao")
    select = FilterableSelect.new(block: Block.bordered(title: "Timezones"))

    screen = render_modal(select, state, 40, 12) |> Enum.join("\n")

    assert screen =~ "Timezones"
    assert screen =~ "America/Sao_Paulo"
    refute screen =~ "Europe/Paris"
  end

  test "small result sets use content-aware modal height" do
    state = State.new(["dark", "light", "high-contrast"])
    select = FilterableSelect.new(block: Block.bordered(title: "Theme"))

    rendered_rows =
      select
      |> render_modal(state, 80, 24)
      |> Enum.count(&(String.trim(&1) != ""))

    assert rendered_rows == 5
  end

  test "content-aware width includes the block title and highlight symbol" do
    title = "A very long content-aware selector title"
    state = State.new(["content-aware option"])

    select =
      FilterableSelect.new(
        block: Block.bordered(title: title, border_type: :double),
        highlight_symbol: ">>>>>> ",
        min_width: 1
      )

    lines = render_modal(select, state, 80, 24)
    screen = Enum.join(lines, "\n")

    assert screen =~ title

    selected_line = Enum.find(lines, &String.contains?(&1, "content-aware option"))
    assert selected_line =~ ">>>>>> content-aware option"
    assert selected_line |> String.trim_trailing() |> String.ends_with?("║")
  end

  test "bounds large lists and stays inside wide, 80-column, and narrow viewports" do
    state = State.new(for n <- 1..30, do: "option #{n}")
    select = FilterableSelect.new(block: Block.bordered(title: "Options"))

    for {width, height} <- [{140, 42}, {80, 24}, {30, 12}] do
      lines = render_modal(select, state, width, height)
      assert Enum.all?(lines, &(String.length(&1) == width))
      assert Enum.count(lines, &(String.trim(&1) != "")) <= min(14, height)
    end
  end

  test "j and k type into the filter; arrows, Ctrl-N/P and Ctrl-J/K move" do
    state = State.new(["jekyll", "work", "kafka"])

    {state, :continue} = State.handle_key(state, {:key, {:char, "k"}, []})
    assert state.filter == "k"
    assert Enum.map(State.filtered(state), & &1.label) == ["jekyll", "work", "kafka"]
    {state, :continue} = State.handle_key(state, {:key, {:char, "j"}, []})
    assert state.filter == "kj"

    state = State.new(["a", "b", "c"])
    {state, :continue} = State.handle_key(state, {:key, {:char, "n"}, [:ctrl]})
    {state, :continue} = State.handle_key(state, {:key, {:char, "j"}, [:ctrl]})
    assert State.selected_value(state) == "c"
    {state, :continue} = State.handle_key(state, {:key, {:char, "p"}, [:ctrl]})
    {state, :continue} = State.handle_key(state, {:key, {:char, "k"}, [:ctrl]})
    {state, :continue} = State.handle_key(state, {:key, :up, []})
    assert State.selected_value(state) == "c"
    assert state.filter == ""
  end

  test "characters typed with Ctrl or Alt are not text" do
    state = State.new(["alpha"])
    assert {^state, :noop} = State.handle_key(state, {:key, {:char, "a"}, [:ctrl]})
    assert {^state, :noop} = State.handle_key(state, {:key, {:char, "x"}, [:alt]})
    {state, :continue} = State.handle_key(state, {:key, {:char, "A"}, [:shift]})
    assert state.filter == "A"
  end

  test "the fuzzy matcher keeps characters in order and puts the best match first" do
    state =
      State.new(["unrelated", "release 0.8", "vibex", "the-release"],
        matcher: :fuzzy,
        filter: "rel"
      )

    assert Enum.map(State.filtered(state), & &1.label) == [
             "release 0.8",
             "the-release",
             "unrelated"
           ]

    state = State.new(["vibex", "vim"], matcher: :fuzzy, filter: "vbx")
    assert [%{label: "vibex"}] = State.filtered(state)
    assert [{%{label: "vibex"}, [0, 2, 4]}] = State.matches(state)
  end

  test "the substring matcher reports the matched characters" do
    state = State.new(["Release 0.8", "notes"], filter: "lea")
    assert [{%{label: "Release 0.8"}, [2, 3, 4]}] = State.matches(state)
    assert [{_, []}, {_, []}] = State.matches(State.new(["a", "b"]))
  end

  test "create: a filter that names no item offers a create row" do
    state = State.new(["bug", "docs"], create: true)
    assert State.create_text(state) == nil

    state = type(state, "rel")
    assert State.filtered(state) == []
    assert State.create_text(state) == "rel"
    assert State.create_selected?(state)
    assert {_state, {:create, "rel"}} = State.handle_key(state, {:key, :enter, []})

    # Matches first, then the create row.
    state = State.new(["bug", "bugfix"], create: true) |> type("bu")
    assert State.create_text(state) == "bu"
    {state, :continue} = State.handle_key(state, {:key, :down, []})
    {state, :continue} = State.handle_key(state, {:key, :down, []})
    assert State.create_selected?(state)
    assert {_state, {:create, "bu"}} = State.handle_key(state, {:key, :enter, []})
    {state, :continue} = State.handle_key(state, {:key, :down, []})
    assert State.selected_value(state) == "bug"
  end

  test "create: no create row when an item has that label, ignoring case and spaces" do
    state = State.new(["Bug"], create: true, filter: " bug ")
    assert State.create_text(state) == nil
    assert {_state, {:confirm, "Bug"}} = State.handle_key(state, {:key, :enter, []})
    assert State.create_text(State.new(["Bug"], filter: "new")) == nil
  end

  test "renders the create row after the matches, in place of the empty label" do
    select = FilterableSelect.new(block: Block.bordered(title: "Tag"))

    screen =
      select
      |> render_modal(State.new(["bug"], create: true, filter: "rel"), 40, 10)
      |> Enum.join("\n")

    assert screen =~ ~s(+ create "rel")
    refute screen =~ "(no matches)"

    lines = render_modal(select, State.new(["bug", "bugfix"], create: true, filter: "bu"), 40, 10)
    rows = Enum.map(lines, &String.trim/1) |> Enum.filter(&(&1 =~ ~r/bug|create/))
    assert [_, _, create] = rows
    assert create =~ ~s(+ create "bu")

    custom = FilterableSelect.new(create_label: &"new tag: #{&1}")

    assert custom |> render_modal(State.new([], create: true, filter: "x"), 40, 10) |> Enum.join() =~
             "new tag: x"
  end

  test "match_style draws the matched characters" do
    select = FilterableSelect.new(match_style: [fg: :yellow], highlight_symbol: "")
    state = State.new(["vibex"], matcher: :fuzzy, filter: "vbx")

    terminal = Terminal.new(backend: TestBackend, backend_opts: [width: 30, height: 5])

    {terminal, _state} =
      Terminal.draw(terminal, &FilterableSelect.render_modal(&1, select, state))

    buffer = terminal |> Terminal.backend_state() |> TestBackend.buffer()

    {x, y} = locate(buffer, "vibex")
    styled = for dx <- 0..4, Buffer.get(buffer, x + dx, y).style.fg == :yellow, do: dx
    assert styled == [0, 2, 4]
  end

  defp type(state, text) do
    text
    |> String.graphemes()
    |> Enum.reduce(state, fn g, st -> elem(State.handle_key(st, {:key, {:char, g}, []}), 0) end)
  end

  defp locate(buffer, text) do
    buffer
    |> Buffer.to_lines()
    |> Enum.with_index()
    |> Enum.find_value(fn {line, y} ->
      case :binary.match(line, text) do
        {x, _} -> {String.length(binary_part(line, 0, x)), y}
        :nomatch -> nil
      end
    end)
  end

  defp render_modal(select, state, width, height) do
    terminal =
      Terminal.new(
        backend: TestBackend,
        backend_opts: [width: width, height: height]
      )

    {terminal, _state} =
      Terminal.draw(terminal, fn frame ->
        FilterableSelect.render_modal(frame, select, state)
      end)

    terminal |> Terminal.backend_state() |> TestBackend.to_lines()
  end
end

defmodule Elui.Widgets.FilterableSelectTest do
  use ExUnit.Case, async: true

  alias Elui.Backend.Test, as: TestBackend
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

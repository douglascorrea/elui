defmodule Elui.Widgets.FilterableSelectTest do
  use ExUnit.Case, async: true

  alias Elui.Buffer
  alias Elui.Frame
  alias Elui.Layout.Rect
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

    area = Rect.new(0, 0, 40, 12)
    frame = %Frame{buffer: Buffer.empty(area), area: area, cursor_position: nil}
    {frame, _state} = FilterableSelect.render_modal(frame, select, state)
    screen = Buffer.to_lines(frame.buffer) |> Enum.join("\n")

    assert screen =~ "Timezones"
    assert screen =~ "America/Sao_Paulo"
    refute screen =~ "Europe/Paris"
  end

  test "small result sets use content-aware modal height" do
    state = State.new(["dark", "light", "high-contrast"])
    select = FilterableSelect.new(block: Block.bordered(title: "Theme"))

    area = Rect.new(0, 0, 80, 24)
    frame = %Frame{buffer: Buffer.empty(area), area: area, cursor_position: nil}
    {frame, _state} = FilterableSelect.render_modal(frame, select, state)

    rendered_rows =
      frame.buffer
      |> Buffer.to_lines()
      |> Enum.count(&(String.trim(&1) != ""))

    assert rendered_rows == 5
  end
end

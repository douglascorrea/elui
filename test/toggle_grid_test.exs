defmodule Elui.Widgets.ToggleGridTest do
  use ExUnit.Case, async: true

  alias Elui.Buffer
  alias Elui.Layout.Rect
  alias Elui.Widgets.ToggleGrid
  alias Elui.Widgets.ToggleGrid.State

  test "renders headers, checked cells, and add row" do
    grid =
      ToggleGrid.new(
        ["Mon", "Tue"],
        [%{label: "10:00", cells: [true, false]}],
        add_label: "+ Add a time"
      )

    screen = render(grid, State.new(focus: {:cell, 0, 0})) |> Enum.join("\n")
    assert screen =~ "Time"
    assert screen =~ "Mon Tue"
    assert screen =~ "10:00"
    assert screen =~ "[x]"
    assert screen =~ "[ ]"
    assert screen =~ "+ Add a time"
  end

  test "State.move navigates cells, row action, and add control" do
    state = State.new(focus: {:cell, 0, 0})
    assert %{focus: {:row_action, 0}} = State.move(state, {0, -1}, 1, 2)
    assert %{focus: {:cell, 0, 0}} = State.move(State.new(focus: {:row_action, 0}), {0, 1}, 1, 2)
    assert %{focus: :add} = State.move(State.new(focus: {:cell, 0, 1}), {1, 0}, 1, 2)
    assert %{focus: {:row_action, 0}} = State.move(State.new(focus: :add), {-1, 0}, 1, 2)
  end

  test "supports app-specific checked and unchecked symbols with a readable gutter" do
    grid =
      ToggleGrid.new(
        ["Mon", "Tue"],
        [%{label: "10:00", cells: [true, false]}],
        checked_symbol: "●",
        unchecked_symbol: "○",
        cell_width: 2
      )

    screen = render(grid, State.new(focus: :add)) |> Enum.join("\n")
    assert screen =~ "● ○"
    refute screen =~ "[x]"
  end

  defp render(grid, state) do
    area = Rect.new(0, 0, 80, 8)
    {buffer, _state} = Elui.StatefulWidget.render(grid, area, Buffer.empty(area), state)
    Buffer.to_lines(buffer)
  end
end

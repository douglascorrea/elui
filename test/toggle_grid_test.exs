defmodule Elui.Widgets.ToggleGridTest do
  use ExUnit.Case, async: true

  alias Elui.Backend.Test, as: TestBackend
  alias Elui.{Frame, Terminal}
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

  test "renders readable default cells at wide, 80-column, and narrow viewports" do
    grid =
      ToggleGrid.new(
        ~w(Mon Tue Wed Thu Fri Sat Sun),
        [%{label: "10:00", cells: [true, false, true, false, true, false, true]}]
      )

    for {width, height} <- [{140, 42}, {80, 24}, {40, 12}] do
      lines = render(grid, State.new(focus: {:cell, 0, 0}), width, height)
      screen = Enum.join(lines, "\n")
      assert screen =~ "Mon Tue Wed"
      assert screen =~ "[x] [ ] [x]"
      assert Enum.all?(lines, &(String.length(&1) == width))
    end
  end

  defp render(grid, state, width \\ 80, height \\ 8) do
    terminal =
      Terminal.new(
        backend: TestBackend,
        backend_opts: [width: width, height: height]
      )

    {terminal, _state} =
      Terminal.draw(terminal, fn frame ->
        Frame.render_stateful_widget(frame, grid, Frame.area(frame), state)
      end)

    terminal |> Terminal.backend_state() |> TestBackend.to_lines()
  end
end

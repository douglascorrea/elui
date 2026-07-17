defmodule Elui.Widgets.WeekGridTest do
  use ExUnit.Case, async: true

  alias Elui.Backend.Test, as: TestBackend
  alias Elui.{Frame, Terminal}
  alias Elui.Layout.Rect
  alias Elui.Widgets.WeekGrid
  alias Elui.Widgets.WeekGrid.State

  test "renders day titles, posts, and unfilled markers" do
    grid =
      WeekGrid.new([
        %{
          title: "Mon 13",
          items: [
            %{text: "13:00 Queued #1", kind: :post},
            %{text: "· 16:00", kind: :marker}
          ]
        },
        %{title: "Tue 14", items: []},
        %{title: "Wed 15", items: []},
        %{title: "Thu 16", items: [%{text: "12:30 Scheduled #2", kind: :post}]},
        %{title: "Fri 17", items: []},
        %{title: "Sat 18", items: []},
        %{title: "Sun 19", items: []}
      ])

    screen = render(grid, State.new(), 98, 8) |> Enum.join("\n")
    assert screen =~ "Mon 13"
    assert screen =~ "13:00 Queued"
    assert screen =~ "· 16:00"
    assert screen =~ "Thu 16"
    assert screen =~ "12:30 Schedu"
  end

  test "overflow shows a +N more marker" do
    items = for n <- 1..6, do: %{text: "line #{n}", kind: :post}

    grid =
      WeekGrid.new([
        %{title: "Mon", items: items},
        %{title: "Tue", items: []},
        %{title: "Wed", items: []},
        %{title: "Thu", items: []},
        %{title: "Fri", items: []},
        %{title: "Sat", items: []},
        %{title: "Sun", items: []}
      ])

    # header + 3 body rows
    screen = render(grid, State.new(), 56, 4) |> Enum.join("\n")
    assert screen =~ "line 1"
    assert screen =~ "line 2"
    assert screen =~ "+4 more"
    refute screen =~ "line 3"
  end

  test "State.move wraps across days and items" do
    counts = fn
      0 -> 2
      1 -> 0
      _ -> 1
    end

    state = State.new(selected_day: 0, selected_item: 0)
    assert %{selected_day: 1, selected_item: 0} = State.move(state, {1, 0}, 7, counts)
    assert %{selected_day: 0, selected_item: 1} = State.move(state, {0, 1}, 7, counts)
    assert %{selected_day: 6} = State.move(state, {-1, 0}, 7, counts)
  end

  test "reports and renders usable columns at wide and 80-column widths" do
    days =
      for day <- ~w(Mon Tue Wed Thu Fri Sat Sun) do
        %{title: day, items: [%{text: "09:00 Q#123", kind: :post}]}
      end

    grid = WeekGrid.new(days, min_column_width: 10)

    for {width, height} <- [{140, 42}, {80, 24}] do
      assert WeekGrid.fits?(grid, Rect.new(0, 0, width, 12))
      lines = render(grid, State.new(), width, height)
      assert Enum.join(lines, "\n") =~ "09:00 Q#123"
      assert Enum.all?(lines, &(String.length(&1) == width))
    end

    refute WeekGrid.fits?(grid, Rect.new(0, 0, 60, 12))
    assert Enum.all?(render(grid, State.new(), 60, 20), &(String.length(&1) == 60))
  end

  defp render(grid, state, width, height) do
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

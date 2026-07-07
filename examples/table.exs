Code.require_file("support/ratatui_port.exs", __DIR__)

# Table example: header, constraint-based column widths and row selection.
#
# Run with:
#
#     mix run examples/table.exs
#
# Use Up/Down to move, `q` to quit.

defmodule Examples.Table do
  @behaviour Elui.App

  alias Elui.Frame
  alias Elui.Widgets.Block
  alias Elui.Widgets.Table
  alias Elui.Widgets.Table.Row

  @rows [
    ["Row 1", "Cell 1-2", "Cell 1-3"],
    ["Row 2", "Cell 2-2", "Cell 2-3"],
    ["Row 3", "Cell 3-2", "Cell 3-3"],
    ["Row 4", "Cell 4-2", "Cell 4-3"],
    ["Row 5", "Cell 5-2", "Cell 5-3"],
    ["Row 6", "Cell 6-2", "Cell 6-3"]
  ]

  @impl true
  def init(_opts), do: %{state: Table.State.new(selected: 0)}

  @impl true
  def update(_model, {:key, {:char, "q"}, _mods}), do: :quit

  def update(model, {:key, :down, _mods}) do
    {:ok, %{model | state: Table.State.select_next(model.state, length(@rows))}}
  end

  def update(model, {:key, :up, _mods}) do
    {:ok, %{model | state: Table.State.select_previous(model.state, length(@rows))}}
  end

  def update(model, _event), do: {:ok, model}

  @impl true
  def view(model, frame) do
    table =
      Table.new(
        Enum.map(@rows, &Row.new/1),
        [{:length, 10}, {:fill, 1}, {:fill, 1}],
        header: Row.new(["Name", "Column 2", "Column 3"], style: [add_modifier: [:bold], fg: :yellow]),
        block: Block.bordered(title: "Table", title_bottom: "↑/↓ to move · q to quit"),
        row_highlight_style: [bg: :blue],
        highlight_symbol: "> "
      )

    {frame, _state} = Frame.render_stateful_widget(frame, table, Frame.area(frame), model.state)
    frame
  end
end

Examples.Support.run(Examples.Table)

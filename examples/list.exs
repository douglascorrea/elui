Code.require_file("support/ratatui_port.exs", __DIR__)

# List example: a selectable, scrollable list with a scrollbar.
#
# Run with:
#
#     mix run examples/list.exs
#
# Use Up/Down (or j/k) to move, Home/End to jump, `q` to quit.

defmodule Examples.List do
  @behaviour Elui.App

  alias Elui.{Frame, Layout}
  alias Elui.Widgets.{Block, Paragraph, Scrollbar}
  alias Elui.Widgets.List, as: UiList

  @items Enum.map(1..50, fn i -> "Item #{i}" end)

  @impl true
  def init(_opts) do
    %{list_state: UiList.State.new(selected: 0)}
  end

  @impl true
  def update(_model, {:key, {:char, "q"}, _mods}), do: :quit

  def update(model, {:key, key, _mods}) when key in [:down, {:char, "j"}] do
    {:ok, %{model | list_state: UiList.State.select_next(model.list_state, length(@items))}}
  end

  def update(model, {:key, key, _mods}) when key in [:up, {:char, "k"}] do
    {:ok, %{model | list_state: UiList.State.select_previous(model.list_state, length(@items))}}
  end

  def update(model, {:key, :home, _mods}) do
    {:ok, %{model | list_state: UiList.State.select_first(model.list_state)}}
  end

  def update(model, {:key, :end, _mods}) do
    {:ok, %{model | list_state: UiList.State.select_last(model.list_state, length(@items))}}
  end

  def update(model, _event), do: {:ok, model}

  @impl true
  def view(model, frame) do
    [main, help] =
      Layout.vertical([{:fill, 1}, {:length, 1}]) |> Layout.split(Frame.area(frame))

    list =
      UiList.new(@items,
        block: Block.bordered(title: "List"),
        highlight_style: [bg: :blue, add_modifier: [:bold]],
        highlight_symbol: "> "
      )

    {frame, list_state} = Frame.render_stateful_widget(frame, list, main, model.list_state)

    scrollbar_state =
      Scrollbar.State.new(length(@items), position: list_state.selected || 0)

    {frame, _} =
      Frame.render_stateful_widget(frame, Scrollbar.new(:vertical_right), main, scrollbar_state)

    _ = list_state

    Frame.render_widget(
      frame,
      Paragraph.new("j/k or arrows to move · Home/End to jump · q to quit"),
      help
    )
  end
end

Examples.Support.run(Examples.List)

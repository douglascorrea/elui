Code.require_file("support/ratatui_port.exs", __DIR__)

# Custom widget demo: three interactive buttons implemented as custom
# Elui.Widget structs. Keyboard and mouse are both supported.
#
# Run with:
#
#     mix run examples/custom_widget.exs

defmodule Examples.CustomWidget do
  @behaviour Elui.App

  alias Elui.{Frame, Layout}
  alias Elui.Examples.Widgets.Button
  alias Elui.Layout.Rect
  alias Elui.Widgets.Block

  @buttons [
    {"Red", :light_red, :red},
    {"Green", :light_green, :green},
    {"Blue", :light_blue, :blue}
  ]

  @impl true
  def init(_opts) do
    %{selected: 0, pressed: MapSet.new(), size: {80, 24}}
  end

  @impl true
  def update(model, event) do
    cond do
      Examples.Support.quit?(event) ->
        :quit

      Examples.Support.key?(event, [:left, {:char, "h"}]) ->
        {:ok, %{model | selected: Examples.Support.cycle(model.selected, -1, length(@buttons))}}

      Examples.Support.key?(event, [:right, {:char, "l"}]) ->
        {:ok, %{model | selected: Examples.Support.cycle(model.selected, 1, length(@buttons))}}

      Examples.Support.key?(event, [:space, :enter]) ->
        {:ok, toggle(model, model.selected)}

      match?({:resize, _, _}, event) ->
        {:resize, width, height} = event
        {:ok, %{model | size: {width, height}}}

      match?({:mouse, _, _, _, _}, event) ->
        handle_mouse(model, event)

      true ->
        {:ok, model}
    end
  end

  @impl true
  def view(model, frame) do
    [header, body, footer] =
      Layout.vertical([{:length, 2}, {:fill, 1}, {:length, 1}])
      |> Layout.split(Frame.area(frame))

    frame =
      Examples.Support.render_header(
        frame,
        header,
        "Custom Widget",
        "left/right select, Space toggle, mouse click"
      )

    frame =
      Frame.render_widget(
        frame,
        Block.bordered(title: "Buttons", border_style: [fg: :dark_gray]),
        body
      )

    button_areas(Frame.area(frame).width, Frame.area(frame).height)
    |> Enum.with_index()
    |> Enum.reduce(frame, fn {area, index}, acc ->
      {label, fg, bg} = Enum.at(@buttons, index)

      Frame.render_widget(
        acc,
        Button.new(label,
          fg: fg,
          bg: bg,
          selected: model.selected == index,
          pressed: MapSet.member?(model.pressed, index)
        ),
        area
      )
    end)
    |> Examples.Support.render_footer(footer, "q/Esc quit")
  end

  defp handle_mouse(model, {:mouse, :move, x, y, _mods}) do
    case button_at(model.size, x, y) do
      nil -> {:ok, model}
      index -> {:ok, %{model | selected: index}}
    end
  end

  defp handle_mouse(model, {:mouse, {:down, :left}, x, y, _mods}) do
    case button_at(model.size, x, y) do
      nil -> {:ok, model}
      index -> {:ok, toggle(%{model | selected: index}, index)}
    end
  end

  defp handle_mouse(model, _event), do: {:ok, model}

  defp toggle(model, index) do
    pressed =
      if MapSet.member?(model.pressed, index) do
        MapSet.delete(model.pressed, index)
      else
        MapSet.put(model.pressed, index)
      end

    %{model | pressed: pressed}
  end

  defp button_at({width, height}, x, y) do
    Rect.new(0, 0, width, height)
    |> then(fn area -> button_areas(area.width, area.height) end)
    |> Enum.find_index(&Rect.contains?(&1, {x, y}))
  end

  defp button_areas(width, height) do
    area = Rect.new(0, 0, width, height)

    [_header, body, _footer] =
      Layout.vertical([{:length, 2}, {:fill, 1}, {:length, 1}])
      |> Layout.split(area)

    buttons = Examples.Support.centered(body, {:percentage, 75}, {:length, 7})

    Layout.horizontal([{:fill, 1}, {:fill, 1}, {:fill, 1}], spacing: 2)
    |> Layout.split(buttons)
  end
end

Examples.Support.run(Examples.CustomWidget, mouse: true)

# Popup example: Clear + a centered rect to draw a modal over content.
#
# Run with:
#
#     mix run examples/popup.exs
#
# Press `p` to toggle the popup, `q` to quit.

defmodule Examples.Popup do
  @behaviour Elui.App

  alias Elui.Frame
  alias Elui.Layout.Rect
  alias Elui.Widgets.{Block, Clear, Paragraph}

  @impl true
  def init(_opts), do: %{show_popup: false}

  @impl true
  def update(_model, {:key, {:char, "q"}, _mods}), do: :quit
  def update(model, {:key, {:char, "p"}, _mods}), do: {:ok, %{model | show_popup: not model.show_popup}}
  def update(model, _event), do: {:ok, model}

  @impl true
  def view(model, frame) do
    background =
      Paragraph.new(
        Enum.map_join(1..200, " ", fn i -> "content #{i}" end),
        wrap: true,
        block: Block.bordered(title: "Background", title_bottom: "p toggles popup · q quits"),
        style: [fg: :dark_gray]
      )

    frame = Frame.render_widget(frame, background, Frame.area(frame))

    if model.show_popup do
      popup_area = Rect.centered(Frame.area(frame), {:percentage, 50}, {:percentage, 40})

      popup =
        Paragraph.new("This is a popup.\n\nPress p to close it.",
          alignment: :center,
          block: Block.bordered(title: "Popup", border_type: :double, border_style: [fg: :yellow])
        )

      frame
      |> Frame.render_widget(Clear.new(), popup_area)
      |> Frame.render_widget(popup, popup_area)
    else
      frame
    end
  end
end

Elui.App.run(Examples.Popup)

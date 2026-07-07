Code.require_file("support/ratatui_port.exs", __DIR__)

# Layout example: constraints, nested splits, flex modes and spacing.
#
# Run with:
#
#     mix run examples/layout.exs
#
# Press `q` to quit.

defmodule Examples.Layout do
  @behaviour Elui.App

  alias Elui.{Frame, Layout}
  alias Elui.Widgets.{Block, Paragraph}

  @impl true
  def init(_opts), do: %{}

  @impl true
  def update(_model, {:key, {:char, "q"}, _mods}), do: :quit
  def update(model, _event), do: {:ok, model}

  @impl true
  def view(_model, frame) do
    [header, body, footer] =
      Layout.vertical([{:length, 3}, {:fill, 1}, {:length, 3}])
      |> Layout.split(Frame.area(frame))

    [left, center, right] =
      Layout.horizontal([{:percentage, 25}, {:fill, 1}, {:min, 20}], spacing: 1)
      |> Layout.split(body)

    [top, bottom] =
      Layout.vertical([{:ratio, 1, 2}, {:ratio, 1, 2}])
      |> Layout.split(center)

    frame
    |> Frame.render_widget(demo_box("Length(3)", :yellow), header)
    |> Frame.render_widget(demo_box("Percentage(25)", :green), left)
    |> Frame.render_widget(demo_box("Ratio(1/2)", :cyan), top)
    |> Frame.render_widget(demo_box("Ratio(1/2)", :blue), bottom)
    |> Frame.render_widget(demo_box("Min(20)", :magenta), right)
    |> Frame.render_widget(demo_box("Length(3) - q to quit", :yellow), footer)
  end

  defp demo_box(label, color) do
    Paragraph.new(label,
      alignment: :center,
      block: Block.bordered(border_style: [fg: color])
    )
  end
end

Examples.Support.run(Examples.Layout)

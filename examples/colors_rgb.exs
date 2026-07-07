Code.require_file("support/ratatui_port.exs", __DIR__)

# Colors-RGB demo: animated truecolor bands.
#
# Run with:
#
#     mix run examples/colors_rgb.exs

defmodule Examples.ColorsRgb do
  @behaviour Elui.App

  alias Elui.{Frame, Layout}
  alias Elui.Text.Line
  alias Elui.Widgets.{Block, Paragraph}

  @impl true
  def init(_opts), do: %{tick: 0}

  @impl true
  def update(model, event) do
    cond do
      Examples.Support.quit?(event) -> :quit
      event == :tick -> {:ok, %{model | tick: model.tick + 4}}
      true -> {:ok, model}
    end
  end

  @impl true
  def view(model, frame) do
    [header, body, footer] =
      Layout.vertical([{:length, 2}, {:fill, 1}, {:length, 1}])
      |> Layout.split(Frame.area(frame))

    width = max(body.width - 4, 1)

    lines =
      0..max(body.height - 4, 0)
      |> Enum.map(fn row -> Line.new(Examples.Support.rgb_gradient(model.tick + row * 18, width)) end)

    frame =
      Examples.Support.render_header(frame, header, "RGB Colors", "animated truecolor background")

    frame =
      Frame.render_widget(
        frame,
        Paragraph.new(lines, block: Block.bordered(title: "24-bit color sweep")),
        body
      )

    Examples.Support.render_footer(frame, footer, "q/Esc quit")
  end
end

Examples.Support.run(Examples.ColorsRgb, tick_rate: 60)

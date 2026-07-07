Code.require_file("support/ratatui_port.exs", __DIR__)

# Inline demo: renders without switching to the alternate screen.
#
# Run with:
#
#     mix run examples/inline.exs

defmodule Examples.Inline do
  @behaviour Elui.App

  alias Elui.{Frame, Layout}
  alias Elui.Widgets.{Block, Gauge, Paragraph}

  @impl true
  def init(_opts), do: %{ratio: 0.0}

  @impl true
  def update(model, event) do
    cond do
      Examples.Support.quit?(event) -> :quit
      event == :tick -> {:ok, %{model | ratio: if(model.ratio >= 1.0, do: 0.0, else: model.ratio + 0.02)}}
      true -> {:ok, model}
    end
  end

  @impl true
  def view(model, frame) do
    area =
      Frame.area(frame)
      |> Examples.Support.centered({:percentage, 80}, {:length, 8})

    [copy, gauge] =
      Layout.vertical([{:fill, 1}, {:length, 3}])
      |> Layout.split(area)

    frame
    |> Frame.render_widget(
      Paragraph.new("This example keeps the normal terminal scrollback visible by disabling the alternate screen.",
        wrap: [trim: true],
        alignment: :center,
        block: Block.bordered(title: "Inline viewport")
      ),
      copy
    )
    |> Frame.render_widget(
      Gauge.new(model.ratio, gauge_style: [fg: :green], block: Block.bordered(title: "Activity")),
      gauge
    )
  end
end

Examples.Support.run(Examples.Inline,
  tick_rate: 80,
  terminal: [backend_opts: [alternate_screen: false]]
)

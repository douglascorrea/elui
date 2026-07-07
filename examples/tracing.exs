Code.require_file("support/ratatui_port.exs", __DIR__)

# Tracing demo: shows a rolling log panel like a tracing subscriber
# output view.
#
# Run with:
#
#     mix run examples/tracing.exs

defmodule Examples.Tracing do
  @behaviour Elui.App

  alias Elui.{Frame, Layout}
  alias Elui.Widgets.{Block, Paragraph}

  @impl true
  def init(_opts), do: %{tick: 0, paused: false}

  @impl true
  def update(model, event) do
    cond do
      Examples.Support.quit?(event) -> :quit
      Examples.Support.key?(event, [:enter, :space]) -> {:ok, %{model | paused: !model.paused}}
      event == :tick and not model.paused -> {:ok, %{model | tick: model.tick + 1}}
      true -> {:ok, model}
    end
  end

  @impl true
  def view(model, frame) do
    [header, body, footer] =
      Layout.vertical([{:length, 2}, {:fill, 1}, {:length, 1}])
      |> Layout.split(Frame.area(frame))

    frame =
      Examples.Support.render_header(frame, header, "Tracing", "Space pause, q quit")

    frame =
      Frame.render_widget(
        frame,
        Paragraph.new(Examples.Support.log_lines(model.tick),
          block: Block.bordered(title: "events"),
          wrap: false
        ),
        body
      )

    Examples.Support.render_footer(frame, footer, if(model.paused, do: "paused", else: "streaming"))
  end
end

Examples.Support.run(Examples.Tracing, tick_rate: 180)

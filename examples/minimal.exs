Code.require_file("support/ratatui_port.exs", __DIR__)

# Minimal demo: the smallest useful Elui app loop, matching Ratatui's
# minimal application shape.
#
# Run with:
#
#     mix run examples/minimal.exs

defmodule Examples.Minimal do
  @behaviour Elui.App

  alias Elui.Frame
  alias Elui.Widgets.{Block, Paragraph}

  @impl true
  def init(_opts), do: %{ticks: 0}

  @impl true
  def update(model, event) do
    cond do
      Examples.Support.quit?(event) -> :quit
      event == :tick -> {:ok, %{model | ticks: model.ticks + 1}}
      true -> {:ok, model}
    end
  end

  @impl true
  def view(model, frame) do
    Frame.render_widget(
      frame,
      Paragraph.new("Hello from Elui.\n\nFrames: #{model.ticks}\nPress q or Esc to quit.",
        alignment: :center,
        block: Block.bordered(title: "Minimal")
      ),
      Frame.area(frame)
    )
  end
end

Examples.Support.run(Examples.Minimal)

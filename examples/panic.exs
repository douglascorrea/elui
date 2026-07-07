Code.require_file("support/ratatui_port.exs", __DIR__)

# Panic demo: proves App.run/2 restores the terminal from its `after`
# block even when update/2 raises.
#
# Run with:
#
#     mix run examples/panic.exs

defmodule Examples.Panic do
  @behaviour Elui.App

  alias Elui.Frame
  alias Elui.Widgets.{Block, Paragraph}

  @impl true
  def init(_opts), do: %{}

  @impl true
  def update(model, event) do
    cond do
      Examples.Support.quit?(event) -> :quit
      Examples.Support.key?(event, {:char, "p"}) -> raise "intentional panic from examples/panic.exs"
      true -> {:ok, model}
    end
  end

  @impl true
  def view(_model, frame) do
    Frame.render_widget(
      frame,
      Paragraph.new("Press p to raise intentionally.\nPress q/Esc to quit safely.",
        alignment: :center,
        block: Block.bordered(title: "Panic")
      ),
      Frame.area(frame)
    )
  end
end

Examples.Support.run(Examples.Panic)

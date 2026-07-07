# Hello world: the smallest possible Elui application.
#
# Run with:
#
#     mix run examples/hello_world.exs
#
# Press `q` to quit.

defmodule Examples.HelloWorld do
  @behaviour Elui.App

  alias Elui.Frame
  alias Elui.Widgets.{Block, Paragraph}

  @impl true
  def init(_opts), do: %{}

  @impl true
  def update(_model, {:key, {:char, "q"}, _mods}), do: :quit
  def update(model, _event), do: {:ok, model}

  @impl true
  def view(_model, frame) do
    paragraph =
      Paragraph.new("Hello, world!\n\nPress q to quit.",
        alignment: :center,
        block: Block.bordered(title: "Elui", border_type: :rounded)
      )

    Frame.render_widget(frame, paragraph, Frame.area(frame))
  end
end

Elui.App.run(Examples.HelloWorld)

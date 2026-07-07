Code.require_file("support/ratatui_port.exs", __DIR__)

# Hyperlink demo: writes an OSC 8 hyperlink sequence into a custom
# widget cell, with a visible fallback URL.
#
# Run with:
#
#     mix run examples/hyperlink.exs

defmodule Examples.Hyperlink do
  @behaviour Elui.App

  alias Elui.{Frame, Layout}
  alias Elui.Examples.Widgets.Hyperlink, as: Link
  alias Elui.Widgets.{Block, Paragraph}

  @url "https://ratatui.rs"

  @impl true
  def init(_opts), do: %{}

  @impl true
  def update(_model, event) do
    if Examples.Support.quit?(event), do: :quit, else: {:ok, %{}}
  end

  @impl true
  def view(_model, frame) do
    [header, body, footer] =
      Layout.vertical([{:length, 2}, {:fill, 1}, {:length, 2}])
      |> Layout.split(Frame.area(frame))

    [link_area, fallback] =
      Layout.vertical([{:fill, 1}, {:length, 4}], spacing: 1)
      |> Layout.split(body)

    frame =
      Examples.Support.render_header(frame, header, "Hyperlink", "OSC 8 terminal hyperlink")

    frame =
      Frame.render_widget(
        frame,
        Block.bordered(title: "Hover/click in terminals that support links", border_style: [fg: :cyan]),
        link_area
      )

    frame = Frame.render_widget(frame, Link.new("Open Ratatui", @url), link_area)

    frame =
      Frame.render_widget(
        frame,
        Paragraph.new("Fallback URL:\n#{@url}", alignment: :center, block: Block.bordered(title: "Plain text")),
        fallback
      )

    Examples.Support.render_footer(frame, footer, "q/Esc quit")
  end
end

Examples.Support.run(Examples.Hyperlink)

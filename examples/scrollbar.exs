Code.require_file("support/ratatui_port.exs", __DIR__)

# Scrollbar demo: vertical and horizontal scrollbars tied to paragraph
# scroll offsets.
#
# Run with:
#
#     mix run examples/scrollbar.exs

defmodule Examples.Scrollbar do
  @behaviour Elui.App

  alias Elui.{Frame, Layout}
  alias Elui.Widgets.{Block, Paragraph, Scrollbar}

  @lines Enum.map(1..120, fn i ->
           String.pad_trailing("Line #{i}", 10) <>
             "The quick brown fox jumps over the lazy terminal viewport #{String.duplicate(".", rem(i, 40))}"
         end)

  @impl true
  def init(_opts), do: %{y: 0, x: 0}

  @impl true
  def update(model, event) do
    cond do
      Examples.Support.quit?(event) -> :quit
      Examples.Support.key?(event, [:down, {:char, "j"}]) -> {:ok, %{model | y: min(model.y + 1, length(@lines) - 1)}}
      Examples.Support.key?(event, [:up, {:char, "k"}]) -> {:ok, %{model | y: max(model.y - 1, 0)}}
      Examples.Support.key?(event, [:page_down, {:char, "f"}]) -> {:ok, %{model | y: min(model.y + 10, length(@lines) - 1)}}
      Examples.Support.key?(event, [:page_up, {:char, "b"}]) -> {:ok, %{model | y: max(model.y - 10, 0)}}
      Examples.Support.key?(event, [:right, {:char, "l"}]) -> {:ok, %{model | x: min(model.x + 2, 80)}}
      Examples.Support.key?(event, [:left, {:char, "h"}]) -> {:ok, %{model | x: max(model.x - 2, 0)}}
      Examples.Support.key?(event, [:home, {:char, "g"}]) -> {:ok, %{model | y: 0, x: 0}}
      Examples.Support.key?(event, [:end, {:char, "G"}]) -> {:ok, %{model | y: length(@lines) - 1}}
      true -> {:ok, model}
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
        "Scrollbar",
        "j/k/f/b vertical, h/l horizontal"
      )

    frame =
      Frame.render_widget(
        frame,
        Paragraph.new(Enum.join(@lines, "\n"),
          block: Block.bordered(title: "Scrollable paragraph"),
          scroll: {model.y, model.x},
          wrap: false
        ),
        body
      )

    {frame, _} =
      Frame.render_stateful_widget(
        frame,
        Scrollbar.new(:vertical_right, thumb_style: [fg: :yellow]),
        body,
        Scrollbar.State.new(length(@lines), position: model.y, viewport_content_length: body.height)
      )

    {frame, _} =
      Frame.render_stateful_widget(
        frame,
        Scrollbar.new(:horizontal_bottom, thumb_style: [fg: :cyan]),
        body,
        Scrollbar.State.new(120, position: model.x, viewport_content_length: body.width)
      )

    Examples.Support.render_footer(frame, footer, "offset y=#{model.y}, x=#{model.x} · q/Esc quit")
  end
end

Examples.Support.run(Examples.Scrollbar)

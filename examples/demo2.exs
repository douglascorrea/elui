Code.require_file("support/ratatui_port.exs", __DIR__)

# Demo2: a compact multi-tab showcase inspired by Ratatui's README
# demo application.
#
# Run with:
#
#     mix run examples/demo2.exs

defmodule Examples.Demo2 do
  @behaviour Elui.App

  alias Elui.{Frame, Layout}
  alias Elui.Text.{Line, Span}
  alias Elui.Widgets.{BarChart, Block, Paragraph, Table, Tabs}
  alias Elui.Widgets.Table.Row

  @tabs ["About", "Email", "Recipe", "Traceroute", "Weather"]

  @impl true
  def init(_opts), do: %{tab: 0, tick: 0, selected: Table.State.new(selected: 0)}

  @impl true
  def update(model, event) do
    cond do
      Examples.Support.quit?(event) ->
        :quit

      Examples.Support.key?(event, [:right, {:char, "l"}]) ->
        {:ok, %{model | tab: Examples.Support.cycle(model.tab, 1, length(@tabs))}}

      Examples.Support.key?(event, [:left, {:char, "h"}]) ->
        {:ok, %{model | tab: Examples.Support.cycle(model.tab, -1, length(@tabs))}}

      Examples.Support.key?(event, [:down, {:char, "j"}]) ->
        {:ok, %{model | selected: Table.State.select_next(model.selected, 5)}}

      Examples.Support.key?(event, [:up, {:char, "k"}]) ->
        {:ok, %{model | selected: Table.State.select_previous(model.selected, 5)}}

      event == :tick ->
        {:ok, %{model | tick: model.tick + 1}}

      true ->
        {:ok, model}
    end
  end

  @impl true
  def view(model, frame) do
    [tabs_area, body, footer] =
      Layout.vertical([{:length, 3}, {:fill, 1}, {:length, 1}])
      |> Layout.split(Frame.area(frame))

    frame =
      Frame.render_widget(
        frame,
        Tabs.new(@tabs,
          selected: model.tab,
          block: Block.bordered(title: "Demo2"),
          highlight_style: [fg: :yellow, add_modifier: [:bold]]
        ),
        tabs_area
      )

    frame =
      case Enum.at(@tabs, model.tab) do
        "About" -> about(frame, body)
        "Email" -> email(frame, body, model)
        "Recipe" -> recipe(frame, body)
        "Traceroute" -> traceroute(frame, body, model.tick)
        "Weather" -> weather(frame, body)
      end

    Examples.Support.render_footer(frame, footer, "h/l tabs, j/k select, q quit")
  end

  defp about(frame, area) do
    Examples.Support.two_column(
      frame,
      area,
      "What it is",
      [
        Line.new([Span.new("Elui", fg: :yellow, add_modifier: [:bold]), Span.new(" is immediate-mode TUI rendering for Elixir.")]),
        Line.new("The app redraws from state on every frame."),
        Line.new("The terminal backend diffs buffers and writes only changed cells.")
      ],
      "Widgets",
      "Tabs, paragraphs, tables, charts, blocks, gauges, canvas, lists, calendars and scrollbars."
    )
  end

  defp email(frame, area, model) do
    rows =
      [
        ["[unread]", "Mara", "Calendar explorer feedback"],
        ["[read]", "Theo", "Demo2 theme polish"],
        ["[unread]", "Jules", "Canvas projection notes"],
        ["[read]", "Nina", "Release checklist"],
        ["[read]", "Omar", "Widget protocol question"]
      ]
      |> Enum.map(&Row.new/1)

    table =
      Table.new(rows, [{:length, 10}, {:length, 12}, {:fill, 1}],
        header: Row.new(["State", "From", "Subject"], style: [fg: :yellow, add_modifier: [:bold]]),
        block: Block.bordered(title: "Inbox"),
        row_highlight_style: [bg: :blue],
        highlight_symbol: "> "
      )

    {frame, _} = Frame.render_stateful_widget(frame, table, area, model.selected)
    frame
  end

  defp recipe(frame, area) do
    lines = [
      Line.new("Lemon terminal cake", style: [fg: :yellow, add_modifier: [:bold]], alignment: :center),
      Line.new(""),
      Line.new("1. Split layout into useful regions."),
      Line.new("2. Render widgets from immutable state."),
      Line.new("3. Handle events with tiny update clauses."),
      Line.new("4. Let the backend diff the frame."),
      Line.new(""),
      Line.new("Serve with tests and a clean commit.")
    ]

    Frame.render_widget(frame, Paragraph.new(lines, block: Block.bordered(title: "Recipe")), area)
  end

  defp traceroute(frame, area, tick) do
    lines =
      1..12
      |> Enum.map(fn hop ->
        ms = 8 + rem(tick + hop * 11, 90)

        Line.new([
          Span.new(String.pad_leading(to_string(hop), 2), fg: :dark_gray),
          Span.new("  10.#{hop}.#{rem(hop * 37, 255)}.1", fg: :cyan),
          Span.new("  #{ms} ms", fg: if(ms > 70, do: :yellow, else: :green))
        ])
      end)

    Frame.render_widget(frame, Paragraph.new(lines, block: Block.bordered(title: "Traceroute")), area)
  end

  defp weather(frame, area) do
    Frame.render_widget(
      frame,
      BarChart.new(
        [{"Mon", 22}, {"Tue", 24}, {"Wed", 27}, {"Thu", 23}, {"Fri", 25}, {"Sat", 29}, {"Sun", 28}],
        block: Block.bordered(title: "Weather"),
        bar_width: 4,
        bar_style: [fg: :light_blue],
        value_style: [fg: :black, bg: :light_blue]
      ),
      area
    )
  end
end

Examples.Support.run(Examples.Demo2, tick_rate: 120)

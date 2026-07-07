# Demo: a multi-tab tour of most Elui widgets, similar in spirit to
# ratatui's demo example.
#
# Run with:
#
#     mix run examples/demo.exs
#
# Left/Right (or h/l) switch tabs, Up/Down move the list, `q` quits.

defmodule Examples.Demo do
  @behaviour Elui.App

  alias Elui.{Frame, Layout}
  alias Elui.Text.{Line, Span}
  alias Elui.Widgets.{BarChart, Block, Calendar, Gauge, LineGauge, Paragraph, Sparkline, Tabs}
  alias Elui.Widgets.List, as: UiList

  @tabs ["Widgets", "Text", "Calendar"]
  @items Enum.map(1..30, fn i -> "List item #{i}" end)

  @impl true
  def init(_opts) do
    %{
      tab: 0,
      progress: 0.0,
      spark: Enum.map(1..80, fn _ -> :rand.uniform(10) end),
      list_state: UiList.State.new(selected: 0)
    }
  end

  @impl true
  def update(_model, {:key, {:char, "q"}, _mods}), do: :quit

  def update(model, {:key, key, _mods}) when key in [:right, {:char, "l"}] do
    {:ok, %{model | tab: rem(model.tab + 1, length(@tabs))}}
  end

  def update(model, {:key, key, _mods}) when key in [:left, {:char, "h"}] do
    {:ok, %{model | tab: rem(model.tab - 1 + length(@tabs), length(@tabs))}}
  end

  def update(model, {:key, :down, _mods}) do
    {:ok, %{model | list_state: UiList.State.select_next(model.list_state, length(@items))}}
  end

  def update(model, {:key, :up, _mods}) do
    {:ok, %{model | list_state: UiList.State.select_previous(model.list_state, length(@items))}}
  end

  def update(model, :tick) do
    progress = if model.progress >= 1.0, do: 0.0, else: model.progress + 0.01
    spark = tl(model.spark) ++ [:rand.uniform(10)]
    {:ok, %{model | progress: progress, spark: spark}}
  end

  def update(model, _event), do: {:ok, model}

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
          block: Block.bordered(title: "Elui demo"),
          highlight_style: [fg: :yellow, add_modifier: [:bold]]
        ),
        tabs_area
      )

    frame =
      case model.tab do
        0 -> widgets_tab(model, frame, body)
        1 -> text_tab(frame, body)
        2 -> calendar_tab(frame, body)
      end

    Frame.render_widget(
      frame,
      Paragraph.new("←/→ switch tab · ↑/↓ move list · q quit", style: [fg: :dark_gray]),
      footer
    )
  end

  defp widgets_tab(model, frame, area) do
    [left, right] =
      Layout.horizontal([{:percentage, 40}, {:fill, 1}]) |> Layout.split(area)

    {frame, _} =
      Frame.render_stateful_widget(
        frame,
        UiList.new(@items,
          block: Block.bordered(title: "List"),
          highlight_style: [bg: :blue],
          highlight_symbol: "> "
        ),
        left,
        model.list_state
      )

    [gauge_area, line_gauge_area, spark_area, bar_area] =
      Layout.vertical([{:length, 3}, {:length, 3}, {:length, 4}, {:fill, 1}])
      |> Layout.split(right)

    frame
    |> Frame.render_widget(
      Gauge.new(model.progress, block: Block.bordered(title: "Gauge"), gauge_style: [fg: :green]),
      gauge_area
    )
    |> Frame.render_widget(
      LineGauge.new(1.0 - model.progress,
        block: Block.bordered(title: "LineGauge"),
        filled_style: [fg: :magenta]
      ),
      line_gauge_area
    )
    |> Frame.render_widget(
      Sparkline.new(model.spark, block: Block.bordered(title: "Sparkline"), style: [fg: :yellow]),
      spark_area
    )
    |> Frame.render_widget(
      BarChart.new(
        model.spark |> Enum.take(8) |> Enum.with_index() |> Enum.map(fn {v, i} -> {"#{i}", v} end),
        block: Block.bordered(title: "BarChart"),
        bar_width: 3,
        bar_style: [fg: :cyan]
      ),
      bar_area
    )
  end

  defp text_tab(frame, area) do
    text = [
      Line.new([
        Span.new("Styled "),
        Span.new("spans", fg: :yellow, add_modifier: [:bold]),
        Span.new(" in a "),
        Span.new("line", fg: :cyan, add_modifier: [:italic])
      ]),
      Line.new(""),
      Line.new("Underlined", style: [add_modifier: [:underlined]]),
      Line.new("Reversed", style: [add_modifier: [:reversed]]),
      Line.new("Crossed out", style: [add_modifier: [:crossed_out]]),
      Line.new(""),
      Line.new("RGB colors:", style: [add_modifier: [:bold]]),
      Line.new([
        Span.new("  red ", fg: {:rgb, 255, 80, 80}),
        Span.new("green ", fg: {:rgb, 80, 255, 80}),
        Span.new("blue", fg: {:rgb, 100, 100, 255})
      ]),
      Line.new(""),
      Line.new("This long paragraph demonstrates word wrapping across the available width of the widget area.")
    ]

    Frame.render_widget(
      frame,
      Paragraph.new(text, block: Block.bordered(title: "Text & styles"), wrap: [trim: true]),
      area
    )
  end

  defp calendar_tab(frame, area) do
    today = Date.utc_today()

    Frame.render_widget(
      frame,
      Calendar.monthly(today,
        show_month_header: true,
        show_weekdays_header: true,
        events: %{today => [fg: :black, bg: :yellow]},
        weekdays_header_style: [fg: :cyan],
        block: Block.bordered(title: "Calendar")
      ),
      area
    )
  end
end

Elui.App.run(Examples.Demo, tick_rate: 100)

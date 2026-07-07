Code.require_file("support/ratatui_port.exs", __DIR__)

# Calendar explorer demo: a year view with Ratatui-style calendar
# modes, holidays, seasons, and selected-day navigation.
#
# Run with:
#
#     mix run examples/calendar_explorer.exs

defmodule Examples.CalendarExplorer do
  @behaviour Elui.App

  alias Elui.{Frame, Layout}
  alias Elui.Layout.Rect
  alias Elui.Text.Line
  alias Elui.Widgets.{Calendar, Paragraph}

  @style_order [
    :default,
    :surrounding,
    :weekdays_header,
    :surrounding_and_weekdays_header,
    :month_header,
    :month_and_weekdays_header
  ]

  @impl true
  def init(_opts), do: %{date: Date.utc_today(), style: :default}

  @impl true
  def update(model, event) do
    cond do
      Examples.Support.key?(event, {:char, "q"}) ->
        :quit

      Examples.Support.key?(event, {:char, "s"}) ->
        {:ok, %{model | style: next_style(model.style)}}

      Examples.Support.key?(event, [:tab, {:char, "n"}]) ->
        {:ok, %{model | date: shift_month(model.date, 1)}}

      Examples.Support.key?(event, [:back_tab, {:char, "p"}]) ->
        {:ok, %{model | date: shift_month(model.date, -1)}}

      Examples.Support.key?(event, [:left, {:char, "h"}]) ->
        {:ok, %{model | date: Date.add(model.date, -1)}}

      Examples.Support.key?(event, [:down, {:char, "j"}]) ->
        {:ok, %{model | date: Date.add(model.date, 7)}}

      Examples.Support.key?(event, [:up, {:char, "k"}]) ->
        {:ok, %{model | date: Date.add(model.date, -7)}}

      Examples.Support.key?(event, [:right, {:char, "l"}]) ->
        {:ok, %{model | date: Date.add(model.date, 1)}}

      true ->
        {:ok, model}
    end
  end

  @impl true
  def view(model, frame) do
    header_lines = [
      Line.new("Calendar Example", style: [add_modifier: [:bold]], alignment: :center),
      Line.new(
        "<q> Quit | <s> Change Style | <n> Next Month | <p> Previous Month, <hjkl> Move",
        alignment: :center
      ),
      Line.new(
        "Current date: #{Date.to_iso8601(model.date)} | Current style: #{style_label(model.style)}",
        alignment: :center
      )
    ]

    [header_area, year_area] =
      Layout.vertical([{:length, length(header_lines)}, {:fill, 1}])
      |> Layout.split(Frame.area(frame))

    frame =
      Frame.render_widget(
        frame,
        Paragraph.new(header_lines),
        header_area
      )

    render_year(frame, Rect.inner(year_area, {1, 1}), model)
  end

  defp render_year(frame, area, model) do
    rows =
      Layout.vertical(List.duplicate({:ratio, 1, 3}, 3))
      |> Layout.split(area)

    rows
    |> Enum.with_index()
    |> Enum.reduce(frame, fn {row_area, row}, acc ->
      Layout.horizontal(List.duplicate({:ratio, 1, 4}, 4))
      |> Layout.split(row_area)
      |> Enum.with_index()
      |> Enum.reduce(acc, fn {month_area, col}, frame ->
        month = row * 4 + col + 1
        date = Date.new!(model.date.year, month, 1)

        Frame.render_widget(
          frame,
          calendar(model.style, date, events(model.date)),
          month_area
        )
      end)
    end)
  end

  defp calendar(style, date, events) do
    base = [
      events: events,
      default_style: [bg: {:rgb, 50, 50, 50}, add_modifier: [:bold]],
      show_month_header: true
    ]

    opts =
      case style do
        :default ->
          base

        :surrounding ->
          Keyword.merge(base,
            show_surrounding: true,
            surrounding_style: [add_modifier: [:dim]]
          )

        :weekdays_header ->
          Keyword.merge(base,
            show_weekdays_header: true,
            weekdays_header_style: [fg: :green, add_modifier: [:bold]]
          )

        :surrounding_and_weekdays_header ->
          Keyword.merge(base,
            show_surrounding: true,
            surrounding_style: [add_modifier: [:dim]],
            show_weekdays_header: true,
            weekdays_header_style: [fg: :green, add_modifier: [:bold]]
          )

        :month_header ->
          Keyword.merge(base,
            month_header_style: [fg: :green, add_modifier: [:bold]]
          )

        :month_and_weekdays_header ->
          Keyword.merge(base,
            show_weekdays_header: true,
            weekdays_header_style: [fg: :light_yellow, add_modifier: [:bold, :dim]]
          )
      end

    Calendar.monthly(date, opts)
  end

  defp events(selected_date) do
    y = selected_date.year

    %{}
    |> Map.put(Date.utc_today(), [bg: :blue, add_modifier: [:bold]])
    |> add_holidays(y)
    |> add_seasons(y)
    |> Map.put(selected_date, [fg: :white, bg: :red, add_modifier: [:bold]])
  end

  defp add_holidays(events, year) do
    holiday_style = [fg: :red, add_modifier: [:underlined]]

    [
      Date.new!(year, 1, 1),
      Date.new!(year + 1, 1, 1),
      Date.new!(year, 2, 2),
      Date.new!(year, 4, 1),
      Date.new!(year, 4, 22),
      Date.new!(year, 5, 4),
      Date.new!(year, 12, 23),
      Date.new!(year, 12, 31)
    ]
    |> Enum.reduce(events, fn date, acc -> Map.put(acc, date, holiday_style) end)
  end

  defp add_seasons(events, year) do
    season_style = [fg: :green, bg: :black, add_modifier: [:underlined]]

    [
      Date.new!(year, 3, 22),
      Date.new!(year, 6, 21),
      Date.new!(year, 9, 22),
      Date.new!(year, 12, 21)
    ]
    |> Enum.reduce(events, fn date, acc -> Map.put(acc, date, season_style) end)
  end

  defp next_style(style) do
    index = Enum.find_index(@style_order, &(&1 == style)) || 0
    Enum.at(@style_order, Examples.Support.cycle(index, 1, length(@style_order)))
  end

  defp style_label(:default), do: "Default"
  defp style_label(:surrounding), do: "Show Surrounding"
  defp style_label(:weekdays_header), do: "Show Weekdays Header"
  defp style_label(:surrounding_and_weekdays_header), do: "Show Surrounding and Weekdays Header"
  defp style_label(:month_header), do: "Show Month Header"
  defp style_label(:month_and_weekdays_header), do: "Show Month Header and Weekdays Header"

  defp shift_month(date, delta) do
    total = date.year * 12 + date.month - 1 + delta
    year = div(total, 12)
    month = rem(total, 12) + 1
    last_day = Date.days_in_month(Date.new!(year, month, 1))
    Date.new!(year, month, min(date.day, last_day))
  end
end

Examples.Support.run(Examples.CalendarExplorer)

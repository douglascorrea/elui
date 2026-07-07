Code.require_file("support/ratatui_port.exs", __DIR__)

# Calendar explorer demo: move a selected day through a year view and
# cycle event styles.
#
# Run with:
#
#     mix run examples/calendar_explorer.exs

defmodule Examples.CalendarExplorer do
  @behaviour Elui.App

  alias Elui.{Frame, Layout}
  alias Elui.Layout.Rect
  alias Elui.Widgets.Calendar

  @styles [
    [fg: :black, bg: :yellow, add_modifier: [:bold]],
    [fg: :white, bg: :blue],
    [fg: :black, bg: :light_green],
    [fg: :light_magenta, add_modifier: [:underlined]]
  ]

  @impl true
  def init(_opts), do: %{date: Date.utc_today(), style: 0}

  @impl true
  def update(model, event) do
    cond do
      Examples.Support.quit?(event) ->
        :quit

      Examples.Support.key?(event, [:right, {:char, "l"}]) ->
        {:ok, %{model | date: Date.add(model.date, 1)}}

      Examples.Support.key?(event, [:left, {:char, "h"}]) ->
        {:ok, %{model | date: Date.add(model.date, -1)}}

      Examples.Support.key?(event, [:down, {:char, "j"}]) ->
        {:ok, %{model | date: Date.add(model.date, 7)}}

      Examples.Support.key?(event, [:up, {:char, "k"}]) ->
        {:ok, %{model | date: Date.add(model.date, -7)}}

      Examples.Support.key?(event, [:tab, {:char, "n"}]) ->
        {:ok, %{model | date: shift_month(model.date, 1)}}

      Examples.Support.key?(event, [:back_tab, {:char, "p"}]) ->
        {:ok, %{model | date: shift_month(model.date, -1)}}

      Examples.Support.key?(event, {:char, "s"}) ->
        {:ok, %{model | style: Examples.Support.cycle(model.style, 1, length(@styles))}}

      true ->
        {:ok, model}
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
        "#{model.date.year} Calendar Explorer",
        "h/j/k/l move, n/p month, s style"
      )

    frame =
      body
      |> Rect.rows(4)
      |> Enum.with_index()
      |> Enum.reduce(frame, fn {row_area, row}, acc ->
        row_area
        |> Rect.columns(3)
        |> Enum.with_index()
        |> Enum.reduce(acc, fn {area, col}, inner ->
          month = row * 3 + col + 1
          first = Date.new!(model.date.year, month, 1)

          Frame.render_widget(
            inner,
            Calendar.monthly(first,
              show_month_header: true,
              show_weekdays_header: true,
              events: events_for(model),
              weekdays_header_style: [fg: :cyan]
            ),
            area
          )
        end)
      end)

    Examples.Support.render_footer(frame, footer, "selected: #{Date.to_iso8601(model.date)}")
  end

  defp events_for(model), do: %{model.date => Enum.at(@styles, model.style)}

  defp shift_month(date, delta) do
    total = date.year * 12 + date.month - 1 + delta
    year = div(total, 12)
    month = rem(total, 12) + 1
    last_day = Date.days_in_month(Date.new!(year, month, 1))
    Date.new!(year, month, min(date.day, last_day))
  end
end

Examples.Support.run(Examples.CalendarExplorer)

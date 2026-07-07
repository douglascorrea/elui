defmodule Elui.Widgets.Calendar do
  @moduledoc """
  A monthly calendar view with per-date styling. Mirrors ratatui's
  `calendar::Monthly`.

  ## Example

      Calendar.monthly(~D[2026-07-06],
        events: %{~D[2026-07-04] => [fg: :red], ~D[2026-07-06] => [add_modifier: [:bold]]},
        show_month_header: true,
        show_weekdays_header: true,
        block: Block.bordered()
      )
  """

  alias Elui.Buffer
  alias Elui.Layout.Rect
  alias Elui.Style
  alias Elui.Widgets.Block

  defstruct display_date: nil,
            events: %{},
            default_style: %Style{},
            show_month_header: false,
            month_header_style: %Style{},
            show_weekdays_header: false,
            weekdays_header_style: %Style{},
            show_surrounding: false,
            surrounding_style: %Style{},
            block: nil

  @type t :: %__MODULE__{}

  @doc """
  Creates a calendar for the month containing `date`.

  Options: `:events` (map of `%Date{}` to style), `:default_style`,
  `:show_month_header`, `:month_header_style`,
  `:show_weekdays_header`, `:weekdays_header_style`,
  `:show_surrounding` (render leading/trailing days of adjacent
  months), `:surrounding_style`, `:block`.
  """
  @spec monthly(Date.t(), Keyword.t()) :: t()
  def monthly(%Date{} = date, opts \\ []) do
    events =
      opts
      |> Keyword.get(:events, %{})
      |> Map.new(fn {d, style} -> {d, Style.to_style(style)} end)

    %__MODULE__{
      display_date: date,
      events: events,
      default_style: Style.to_style(Keyword.get(opts, :default_style)),
      show_month_header: Keyword.get(opts, :show_month_header, false),
      month_header_style: Style.to_style(Keyword.get(opts, :month_header_style)),
      show_weekdays_header: Keyword.get(opts, :show_weekdays_header, false),
      weekdays_header_style: Style.to_style(Keyword.get(opts, :weekdays_header_style)),
      show_surrounding: Keyword.get(opts, :show_surrounding, false),
      surrounding_style: Style.to_style(Keyword.get(opts, :surrounding_style)),
      block: Keyword.get(opts, :block)
    }
  end

  @months ~w(January February March April May June July August September October November December)

  @doc false
  def render_into(%__MODULE__{} = cal, area, buffer) do
    {inner, buffer} = Block.render_with_block(cal.block, area, buffer)

    if Rect.empty?(inner) do
      buffer
    else
      date = cal.display_date
      y = inner.y

      {buffer, y} =
        if cal.show_month_header do
          header = "#{Enum.at(@months, date.month - 1)} #{date.year}"
          line = Elui.Text.Line.new(header, style: cal.month_header_style, alignment: :center)
          {buf, _} = Buffer.set_line(buffer, inner.x, y, line, inner.width)
          {buf, y + 1}
        else
          {buffer, y}
        end

      {buffer, y} =
        if cal.show_weekdays_header do
          header = " Su Mo Tu We Th Fr Sa"
          buf = Buffer.set_string(buffer, inner.x, y, header, cal.weekdays_header_style)
          {buf, y + 1}
        else
          {buffer, y}
        end

      first = Date.beginning_of_month(date)
      last = Date.end_of_month(date)

      # Day of week with Sunday = 0
      first_dow = rem(Date.day_of_week(first), 7)

      # Grid starts on the Sunday on or before the 1st.
      grid_start = Date.add(first, -first_dow)

      weeks =
        Stream.iterate(grid_start, &Date.add(&1, 7))
        |> Enum.take_while(fn week_start -> Date.compare(week_start, last) != :gt end)

      weeks
      |> Enum.with_index()
      |> Enum.reduce(buffer, fn {week_start, row}, buf ->
        row_y = y + row

        if row_y >= Rect.bottom(inner) do
          buf
        else
          Enum.reduce(0..6, buf, fn dow, b ->
            day = Date.add(week_start, dow)
            in_month? = day.month == date.month and day.year == date.year

            cond do
              not in_month? and not cal.show_surrounding ->
                b

              true ->
                style =
                  cond do
                    not in_month? ->
                      cal.surrounding_style

                    Map.has_key?(cal.events, day) ->
                      Style.patch(cal.default_style, cal.events[day])

                    true ->
                      cal.default_style
                  end

                text = day.day |> Integer.to_string() |> String.pad_leading(3)
                Buffer.set_string(b, inner.x + dow * 3, row_y, text, style)
            end
          end)
        end
      end)
    end
  end

  defimpl Elui.Widget do
    def render(calendar, area, buffer) do
      Elui.Widgets.Calendar.render_into(calendar, area, buffer)
    end
  end
end

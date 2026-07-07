defmodule Elui.Widgets.BarChart.Bar do
  @moduledoc "A single bar in a `Elui.Widgets.BarChart`."

  alias Elui.Style

  defstruct value: 0, label: nil, style: %Style{}, value_style: %Style{}, text_value: nil

  @type t :: %__MODULE__{}

  @spec new(number(), Keyword.t()) :: t()
  def new(value, opts \\ []) do
    %__MODULE__{
      value: value,
      label: Keyword.get(opts, :label),
      style: Style.to_style(Keyword.get(opts, :style)),
      value_style: Style.to_style(Keyword.get(opts, :value_style)),
      text_value: Keyword.get(opts, :text_value)
    }
  end
end

defmodule Elui.Widgets.BarChart.BarGroup do
  @moduledoc "A labelled group of bars in a `Elui.Widgets.BarChart`."

  alias Elui.Widgets.BarChart.Bar

  defstruct label: nil, bars: []

  @type t :: %__MODULE__{}

  @spec new([Bar.t()], Keyword.t()) :: t()
  def new(bars, opts \\ []) do
    %__MODULE__{bars: bars, label: Keyword.get(opts, :label)}
  end
end

defmodule Elui.Widgets.BarChart do
  @moduledoc """
  A vertical or horizontal bar chart with labelled bars and groups.
  Mirrors ratatui's `BarChart`.

  ## Example

      BarChart.new(
        [{"B0", 3}, {"B1", 7}, {"B2", 5}],
        block: Block.bordered(title: "BarChart"),
        bar_width: 3,
        bar_style: [fg: :yellow],
        value_style: [fg: :black, bg: :yellow]
      )
  """

  alias Elui.Buffer
  alias Elui.Layout.Rect
  alias Elui.Style
  alias Elui.Text.Line
  alias Elui.Widgets.BarChart.{Bar, BarGroup}
  alias Elui.Widgets.Block

  defstruct groups: [],
            block: nil,
            style: %Style{},
            bar_style: %Style{},
            value_style: %Style{},
            label_style: %Style{},
            bar_width: 1,
            bar_gap: 1,
            group_gap: 0,
            max: nil,
            direction: :vertical

  @type t :: %__MODULE__{}

  @doc """
  Creates a bar chart.

  `data` may be a list of `{label, value}` tuples, `Bar` structs, or
  `BarGroup` structs.

  Options: `:block`, `:style`, `:bar_style`, `:value_style`,
  `:label_style`, `:bar_width`, `:bar_gap`, `:group_gap`, `:max`,
  `:direction` (`:vertical` or `:horizontal`).
  """
  @spec new([{term(), number()} | Bar.t() | BarGroup.t()], Keyword.t()) :: t()
  def new(data, opts \\ []) do
    groups =
      cond do
        Enum.all?(data, &match?(%BarGroup{}, &1)) ->
          data

        true ->
          bars =
            Enum.map(data, fn
              %Bar{} = bar -> bar
              {label, value} -> Bar.new(value, label: to_string(label))
            end)

          [%BarGroup{bars: bars}]
      end

    %__MODULE__{
      groups: groups,
      block: Keyword.get(opts, :block),
      style: Style.to_style(Keyword.get(opts, :style)),
      bar_style: Style.to_style(Keyword.get(opts, :bar_style)),
      value_style: Style.to_style(Keyword.get(opts, :value_style)),
      label_style: Style.to_style(Keyword.get(opts, :label_style)),
      bar_width: Keyword.get(opts, :bar_width, 1),
      bar_gap: Keyword.get(opts, :bar_gap, 1),
      group_gap: Keyword.get(opts, :group_gap, 0),
      max: Keyword.get(opts, :max),
      direction: Keyword.get(opts, :direction, :vertical)
    }
  end

  @doc false
  def render_into(%__MODULE__{} = chart, area, buffer) do
    buffer = Buffer.set_style(buffer, area, chart.style)
    {inner, buffer} = Block.render_with_block(chart.block, area, buffer)

    all_bars = Enum.flat_map(chart.groups, & &1.bars)

    if Rect.empty?(inner) or all_bars == [] do
      buffer
    else
      max_value = chart.max || all_bars |> Enum.map(& &1.value) |> Enum.max(fn -> 1 end)
      max_value = max(max_value, 1)

      case chart.direction do
        :vertical -> render_vertical(chart, inner, buffer, max_value)
        :horizontal -> render_horizontal(chart, inner, buffer, max_value)
      end
    end
  end

  defp render_vertical(chart, inner, buffer, max_value) do
    has_group_labels = Enum.any?(chart.groups, &(&1.label != nil))
    label_height = 1 + if has_group_labels, do: 1, else: 0
    chart_height = max(inner.height - label_height, 1)
    levels = Elui.Symbols.Bar.nine_levels()

    {buffer, _x} =
      Enum.reduce(chart.groups, {buffer, inner.x}, fn group, {buf, group_x} ->
        {buf, x_after} =
          Enum.reduce(group.bars, {buf, group_x}, fn bar, {b, x} ->
            if x + chart.bar_width > Rect.right(inner) do
              {b, x}
            else
              bar_style = Style.patch(chart.bar_style, bar.style)
              total_eighths = round(bar.value / max_value * chart_height * 8)

              b =
                Enum.reduce(0..(chart_height - 1)//1, b, fn row, acc ->
                  y = inner.y + chart_height - 1 - row
                  remaining = total_eighths - row * 8

                  symbol =
                    cond do
                      remaining >= 8 -> Enum.at(levels, 8)
                      remaining > 0 -> Enum.at(levels, remaining)
                      true -> nil
                    end

                  if symbol do
                    Enum.reduce(0..(chart.bar_width - 1)//1, acc, fn dx, a ->
                      Buffer.put(a, x + dx, y, Elui.Buffer.Cell.new(symbol, bar_style))
                    end)
                  else
                    acc
                  end
                end)

              # Value on top of the bar
              value_text = bar.text_value || to_string(bar.value)

              b =
                if String.length(value_text) <= chart.bar_width and total_eighths >= 8 do
                  value_style = Style.patch(chart.value_style, bar.value_style)
                  vx = x + div(chart.bar_width - String.length(value_text), 2)
                  Buffer.set_string(b, vx, inner.y + chart_height - 1, value_text, value_style)
                else
                  b
                end

              # Bar label
              b =
                if bar.label do
                  label = Line.to_line(bar.label)

                  label = %{
                    label
                    | alignment: :center,
                      style: Style.patch(chart.label_style, label.style)
                  }

                  {b, _} = Buffer.set_line(b, x, inner.y + chart_height, label, chart.bar_width)
                  b
                else
                  b
                end

              {b, x + chart.bar_width + chart.bar_gap}
            end
          end)

        buf =
          if group.label do
            group_width = max(x_after - chart.bar_gap - group_x, 0)
            label = Line.to_line(group.label)

            label = %{
              label
              | alignment: :center,
                style: Style.patch(chart.label_style, label.style)
            }

            {buf2, _} =
              Buffer.set_line(buf, group_x, inner.y + chart_height + 1, label, group_width)

            buf2
          else
            buf
          end

        {buf, x_after + chart.group_gap}
      end)

    buffer
  end

  defp render_horizontal(chart, inner, buffer, max_value) do
    label_width =
      chart.groups
      |> Enum.flat_map(& &1.bars)
      |> Enum.map(fn bar -> if bar.label, do: String.length(to_string(bar.label)), else: 0 end)
      |> Enum.max(fn -> 0 end)

    bars_x = inner.x + label_width + if label_width > 0, do: 1, else: 0
    bars_width = max(Rect.right(inner) - bars_x, 1)

    {buffer, _y} =
      Enum.reduce(chart.groups, {buffer, inner.y}, fn group, {buf, group_y} ->
        {buf, y_after} =
          Enum.reduce(group.bars, {buf, group_y}, fn bar, {b, y} ->
            if y + chart.bar_width > Rect.bottom(inner) do
              {b, y}
            else
              bar_style = Style.patch(chart.bar_style, bar.style)
              filled = round(bar.value / max_value * bars_width)

              b =
                if bar.label do
                  Buffer.set_string(b, inner.x, y, to_string(bar.label), chart.label_style)
                else
                  b
                end

              b =
                Enum.reduce(0..(chart.bar_width - 1)//1, b, fn dy, acc ->
                  Enum.reduce(0..(filled - 1)//1, acc, fn dx, a ->
                    Buffer.put(a, bars_x + dx, y + dy, Elui.Buffer.Cell.new("█", bar_style))
                  end)
                end)

              value_text = bar.text_value || to_string(bar.value)

              b =
                if filled >= String.length(value_text) do
                  value_style = Style.patch(chart.value_style, bar.value_style)
                  Buffer.set_string(b, bars_x, y, value_text, value_style)
                else
                  b
                end

              {b, y + chart.bar_width + chart.bar_gap}
            end
          end)

        {buf, y_after + chart.group_gap}
      end)

    buffer
  end

  defimpl Elui.Widget do
    def render(chart, area, buffer), do: Elui.Widgets.BarChart.render_into(chart, area, buffer)
  end
end

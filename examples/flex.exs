Code.require_file("support/ratatui_port.exs", __DIR__)

# Flex demo: a scrollable gallery of Elui layout flex modes, spacing
# and constraint interactions.
#
# Run with:
#
#     mix run examples/flex.exs

defmodule Examples.Flex do
  @behaviour Elui.App

  alias Elui.Buffer
  alias Elui.Buffer.Cell
  alias Elui.{Frame, Layout}
  alias Elui.Layout.Rect
  alias Elui.Text.{Line, Span}
  alias Elui.Widgets.{Block, Paragraph, Scrollbar, Tabs}

  @tabs [
    {:legacy, "Legacy", :light_yellow},
    {:start, "Start", :light_cyan},
    {:center, "Center", :cyan},
    {:end, "End", :light_blue},
    {:space_around, "SpaceAround", :magenta},
    {:space_evenly, "SpaceEvenly", :light_magenta},
    {:space_between, "SpaceBetween", :blue}
  ]

  @examples [
    {"Min(u16) takes any excess space always",
     [{:length, 10}, {:min, 10}, {:max, 10}, {:percentage, 10}, {:ratio, 1, 10}]},
    {"Fill(u16) takes any excess space always",
     [{:length, 20}, {:percentage, 20}, {:ratio, 1, 5}, {:fill, 1}]},
    {"Here's all constraints in one line",
     [{:length, 10}, {:min, 10}, {:max, 10}, {:percentage, 10}, {:ratio, 1, 10}, {:fill, 1}]},
    {"", [{:max, 50}, {:min, 50}]},
    {"", [{:max, 20}, {:length, 10}]},
    {"", [{:max, 20}, {:length, 10}]},
    {"Min grows always but also allows Fill to grow",
     [{:percentage, 50}, {:fill, 1}, {:fill, 2}, {:min, 50}]},
    {"In `Legacy`, the last constraint of lowest priority takes excess space",
     [{:length, 20}, {:length, 20}, {:percentage, 20}]},
    {"", [{:length, 20}, {:percentage, 20}, {:length, 20}]},
    {"A lowest priority constraint will be broken before a high priority constraint",
     [{:ratio, 1, 4}, {:percentage, 20}]},
    {"`Length` is higher priority than `Percentage`", [{:percentage, 20}, {:length, 10}]},
    {"`Min/Max` is higher priority than `Length`", [{:length, 10}, {:max, 20}]},
    {"", [{:length, 100}, {:min, 20}]},
    {"`Length` is higher priority than `Min/Max`", [{:max, 20}, {:length, 10}]},
    {"", [{:min, 20}, {:length, 90}]},
    {"Fill is the lowest priority and will fill any excess space", [{:fill, 1}, {:ratio, 1, 4}]},
    {"Fill can be used to scale proportionally with other Fill blocks",
     [{:fill, 1}, {:percentage, 20}, {:fill, 2}]},
    {"", [{:ratio, 1, 3}, {:percentage, 20}, {:ratio, 2, 3}]},
    {"Legacy will stretch the last lowest priority constraint\nStretch will only stretch equal weighted constraints",
     [{:length, 20}, {:length, 15}]},
    {"", [{:percentage, 20}, {:length, 15}]},
    {"`Fill(u16)` fills up excess space, but is lower priority to spacers.\ni.e. Fill will only have widths in Flex::Stretch and Flex::Legacy",
     [{:fill, 1}, {:fill, 1}]},
    {"", [{:length, 20}, {:length, 20}]},
    {"When not using `Flex::Stretch` or `Flex::Legacy`,\n`Min(u16)` and `Max(u16)` collapse to their lowest values",
     [{:min, 20}, {:max, 20}]},
    {"", [{:max, 20}]},
    {"", [{:min, 20}, {:max, 20}, {:length, 20}, {:length, 20}]},
    {"", [{:fill, 0}, {:fill, 0}]},
    {"`Fill(1)` can be to scale with respect to other `Fill(2)`", [{:fill, 1}, {:fill, 2}]},
    {"", [{:fill, 1}, {:min, 10}, {:max, 10}, {:fill, 2}]},
    {"`Fill(0)` collapses if there are other non-zero `Fill(_)`\nconstraints. e.g. `[Fill(0), Fill(0), Fill(1)]`:",
     [{:fill, 0}, {:fill, 0}, {:fill, 1}]}
  ]

  @impl true
  def init(_opts), do: %{tab: 0, scroll: 0, spacing: 0, size: {80, 24}}

  @impl true
  def update(model, event) do
    cond do
      Examples.Support.quit?(event) ->
        :quit

      Examples.Support.key?(event, [:right, {:char, "l"}]) ->
        {:ok, %{model | tab: min(model.tab + 1, length(@tabs) - 1)}}

      Examples.Support.key?(event, [:left, {:char, "h"}]) ->
        {:ok, %{model | tab: max(model.tab - 1, 0)}}

      Examples.Support.key?(event, [:down, {:char, "j"}]) ->
        {:ok, clamp_scroll(%{model | scroll: model.scroll + 1})}

      Examples.Support.key?(event, [:up, {:char, "k"}]) ->
        {:ok, %{model | scroll: max(model.scroll - 1, 0)}}

      Examples.Support.key?(event, [:home, {:char, "g"}]) ->
        {:ok, %{model | scroll: 0}}

      Examples.Support.key?(event, [:end, {:char, "G"}]) ->
        {:ok, %{model | scroll: max_scroll(model)}}

      Examples.Support.key?(event, [{:char, "+"}, {:char, "="}]) ->
        {:ok, %{model | spacing: model.spacing + 1}}

      Examples.Support.key?(event, {:char, "-"}) ->
        {:ok, %{model | spacing: max(model.spacing - 1, 0)}}

      match?({:resize, _, _}, event) ->
        {:resize, width, height} = event
        {:ok, clamp_scroll(%{model | size: {width, height}})}

      true ->
        {:ok, model}
    end
  end

  @impl true
  def view(model, frame) do
    [tabs_area, axis_area, demo_area] =
      Layout.vertical([{:length, 3}, {:length, 1}, {:fill, 1}])
      |> Layout.split(Frame.area(frame))

    {_mode, _label, tab_color} = Enum.at(@tabs, model.tab)
    scroll = min(model.scroll, max_scroll(model))
    scrollbar? = content_height() > demo_area.height or scroll > 0
    axis_width = max(demo_area.width - if(scrollbar?, do: 1, else: 0), 0)

    frame =
      Frame.render_widget(
        frame,
        Tabs.new(tab_titles(),
          selected: model.tab,
          block:
            Block.new(
              title: Line.new("Flex Layouts", style: [fg: tab_color, add_modifier: [:bold]]),
              title_bottom: " h/l tab, j/k scroll, g/G top/bottom, +/- spacing "
            ),
          highlight_style: [add_modifier: [:reversed]],
          divider: " ",
          padding: {"", ""}
        ),
        tabs_area
      )

    frame =
      Frame.render_widget(
        frame,
        Paragraph.new(axis(axis_width, model.spacing), alignment: :center, style: [fg: :dark_gray]),
        axis_area
      )

    frame = render_demo(frame, demo_area, %{model | scroll: scroll}, scrollbar?)

    if scrollbar? do
      {frame, _} =
        Frame.render_stateful_widget(
          frame,
          Scrollbar.new(:vertical_right, thumb_style: [fg: tab_color]),
          demo_area,
          Scrollbar.State.new(content_height(),
            position: scroll,
            viewport_content_length: demo_area.height
          )
        )

      frame
    else
      frame
    end
  end

  defp tab_titles do
    Enum.map(@tabs, fn {_mode, label, color} ->
      Line.new(" #{label} ", style: [fg: color, bg: :black])
    end)
  end

  defp axis(width, spacing) do
    label =
      if spacing == 0 do
        "#{width} px"
      else
        "#{width} px (gap: #{spacing} px)"
      end

    bar_width = max(width - 2, String.length(label))
    "<#{String.pad_leading(label, div(bar_width + String.length(label), 2), "-") |> String.pad_trailing(bar_width, "-")}>"
  end

  defp render_demo(frame, area, model, scrollbar?) do
    content_width = area.width - if(scrollbar?, do: 1, else: 0)

    if area.width == 0 or area.height == 0 or content_width <= 0 do
      frame
    else
      content_area = Rect.new(0, 0, content_width, content_height())
      demo_buffer = Buffer.empty(content_area)
      {mode, _label, _color} = Enum.at(@tabs, model.tab)

      demo_buffer =
        @examples
        |> Enum.reduce({demo_buffer, 0}, fn {description, constraints}, {buffer, y} ->
          height = description_height(description) + 4
          example_area = Rect.new(0, y, content_width, height)
          {render_example(buffer, example_area, description, constraints, mode, model.spacing), y + height}
        end)
        |> elem(0)

      visible =
        for y <- 0..(area.height - 1)//1,
            x <- 0..(area.width - 1)//1,
            into: frame.buffer.cells do
          source =
            if x < content_width do
              Buffer.get(demo_buffer, x, model.scroll + y)
            else
              Cell.empty()
            end

          {{area.x + x, area.y + y}, source}
        end

      %{frame | buffer: %{frame.buffer | cells: visible}}
    end
  end

  defp render_example(buffer, area, description, constraints, mode, spacing) do
    title_height = description_height(description)

    [title_area, illustration_area] =
      Layout.vertical([{:length, title_height}, {:fill, 1}])
      |> Layout.split(area)

    buffer =
      if description == "" do
        buffer
      else
        lines =
          description
          |> String.split("\n")
          |> Enum.map(fn line ->
            Line.new([Span.new("// #{line}", fg: :dark_gray, add_modifier: [:italic])])
          end)

        Elui.Widget.render(Paragraph.new(lines), title_area, buffer)
      end

    block_areas =
      Layout.horizontal(constraints, flex: mode, spacing: spacing)
      |> Layout.split(illustration_area)

    buffer =
      Enum.zip(block_areas, constraints)
      |> Enum.reduce(buffer, fn {block_area, constraint}, acc ->
        render_constraint(acc, block_area, constraint)
      end)

    block_areas
    |> spacer_areas(illustration_area)
    |> Enum.reduce(buffer, &render_spacer(&2, &1))
  end

  defp render_constraint(buffer, area, constraint) do
    color = color_for(constraint)
    label = label_for(constraint)

    content = [
      Line.new(label, style: [fg: :white, bg: color, add_modifier: [:bold]], alignment: :center),
      Line.new("#{area.width} px", style: [fg: :white, bg: color], alignment: :center)
    ]

    widget =
      Paragraph.new(content,
        alignment: :center,
        style: [fg: :white, bg: color],
        block:
          Block.bordered(
            border_type: :quadrant_outside,
            border_style: [fg: color, add_modifier: [:reversed]],
            style: [fg: :white, bg: color]
          )
      )

    Elui.Widget.render(widget, area, buffer)
  end

  defp render_spacer(buffer, %Rect{width: 0}), do: buffer

  defp render_spacer(buffer, area) do
    label =
      cond do
        area.width > 4 -> "#{area.width} px"
        area.width > 2 -> "#{area.width}"
        true -> ""
      end

    Elui.Widget.render(
      Paragraph.new(["", "", Line.new(label, style: [fg: :dark_gray], alignment: :center)],
        alignment: :center,
        style: [fg: :dark_gray],
        block: Block.bordered(border_style: [fg: :dark_gray])
      ),
      area,
      buffer
    )
  end

  defp spacer_areas([], area), do: [area]

  defp spacer_areas(blocks, area) do
    blocks = Enum.sort_by(blocks, & &1.x)
    {spacers, cursor} = leading_and_between_spacers(blocks, area)
    end_width = max(Rect.right(area) - cursor, 0)

    if end_width > 0 do
      spacers ++ [Rect.new(cursor, area.y, end_width, area.height)]
    else
      spacers
    end
  end

  defp leading_and_between_spacers(blocks, area) do
    Enum.reduce(blocks, {[], area.x}, fn block, {spacers, cursor} ->
      gap = block.x - cursor

      spacers =
        if gap > 0 do
          spacers ++ [Rect.new(cursor, area.y, gap, area.height)]
        else
          spacers
        end

      {spacers, max(cursor, Rect.right(block))}
    end)
  end

  defp content_height do
    Enum.reduce(@examples, 0, fn {description, _constraints}, total ->
      total + description_height(description) + 4
    end)
  end

  defp description_height(""), do: 0
  defp description_height(description), do: description |> String.split("\n") |> length()

  defp max_scroll(%{size: {_width, height}}) do
    demo_height = max(height - 4, 0)
    max(content_height() - demo_height, 0)
  end

  defp clamp_scroll(model), do: %{model | scroll: min(model.scroll, max_scroll(model))}

  defp label_for({:length, n}), do: "Length(#{n})"
  defp label_for({:min, n}), do: "Min(#{n})"
  defp label_for({:max, n}), do: "Max(#{n})"
  defp label_for({:percentage, n}), do: "Percentage(#{n})"
  defp label_for({:ratio, n, d}), do: "Ratio(#{n}, #{d})"
  defp label_for({:fill, n}), do: "Fill(#{n})"

  defp color_for({:min, _}), do: {:rgb, 30, 64, 175}
  defp color_for({:max, _}), do: {:rgb, 37, 99, 235}
  defp color_for({:length, _}), do: {:rgb, 51, 65, 85}
  defp color_for({:percentage, _}), do: {:rgb, 30, 41, 59}
  defp color_for({:ratio, _, _}), do: {:rgb, 15, 23, 42}
  defp color_for({:fill, _}), do: {:rgb, 2, 6, 23}
end

Examples.Support.run(Examples.Flex)

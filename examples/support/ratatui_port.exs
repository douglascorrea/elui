defmodule Examples.Support do
  @moduledoc false

  alias Elui.{Frame, Layout}
  alias Elui.Layout.Rect
  alias Elui.Text.{Line, Span}
  alias Elui.Widgets.{Block, Paragraph}

  @ansi_colors [
    {"Black", :black},
    {"Red", :red},
    {"Green", :green},
    {"Yellow", :yellow},
    {"Blue", :blue},
    {"Magenta", :magenta},
    {"Cyan", :cyan},
    {"Gray", :gray},
    {"Dark Gray", :dark_gray},
    {"Light Red", :light_red},
    {"Light Green", :light_green},
    {"Light Yellow", :light_yellow},
    {"Light Blue", :light_blue},
    {"Light Magenta", :light_magenta},
    {"Light Cyan", :light_cyan},
    {"White", :white}
  ]

  @doc "Runs an example unless examples are being compiled by tests."
  def run(module, opts \\ []) do
    if System.get_env("ELUI_SKIP_EXAMPLE_RUN") == "1" do
      :ok
    else
      Elui.App.run(module, opts)
    end
  end

  def ansi_colors, do: @ansi_colors

  def quit?(event)
  def quit?({:key, {:char, "q"}, _mods}), do: true
  def quit?({:key, :esc, _mods}), do: true
  def quit?(_event), do: false

  def key?({:key, key, _mods}, keys), do: key in List.wrap(keys)
  def key?(_event, _keys), do: false

  def cycle(index, delta, count) when count > 0 do
    rem(index + delta + count, count)
  end

  def cycle(index, _delta, _count), do: index

  def clamp(value, min, max) when min <= max do
    value |> Kernel.max(min) |> Kernel.min(max)
  end

  def centered(area, width_constraint, height_constraint) do
    Rect.centered(area, width_constraint, height_constraint)
  end

  def render_header(frame, area, title, help \\ nil) do
    title_line =
      Line.new(
        [
          Span.new(title, fg: :yellow, add_modifier: [:bold]),
          Span.new(if(help, do: "  #{help}", else: ""), fg: :dark_gray)
        ],
        alignment: :center
      )

    Frame.render_widget(frame, Paragraph.new([title_line]), area)
  end

  def render_footer(frame, area, text) do
    Frame.render_widget(frame, Paragraph.new(text, style: [fg: :dark_gray]), area)
  end

  def render_panel(frame, area, title, content, opts \\ []) do
    block =
      Block.bordered(
        title: title,
        border_style: Keyword.get(opts, :border_style, [fg: :dark_gray]),
        title_style: Keyword.get(opts, :title_style, [fg: :yellow, add_modifier: [:bold]]),
        padding: Keyword.get(opts, :padding, 0)
      )

    Frame.render_widget(
      frame,
      Paragraph.new(content,
        block: block,
        wrap: Keyword.get(opts, :wrap, [trim: true]),
        alignment: Keyword.get(opts, :alignment)
      ),
      area
    )
  end

  def two_column(frame, area, left_title, left_content, right_title, right_content) do
    [left, right] =
      Layout.horizontal([{:percentage, 50}, {:fill, 1}], spacing: 1)
      |> Layout.split(area)

    frame
    |> render_panel(left, left_title, left_content)
    |> render_panel(right, right_title, right_content)
  end

  def palette_lines do
    Enum.map(@ansi_colors, fn {name, color} ->
      Line.new([
        Span.new("  #{String.pad_trailing(name, 13)}", fg: :black, bg: color),
        Span.new("  "),
        Span.new("#{inspect(color)}", fg: color)
      ])
    end)
  end

  def rgb_gradient(step, width) do
    width = max(width, 1)

    for x <- 0..(width - 1) do
      hue = rem(step + x * 6, 360)
      {r, g, b} = hsv_to_rgb(hue, 0.85, 0.95)
      Span.new(" ", bg: {:rgb, r, g, b})
    end
  end

  def sample_pull_requests do
    [
      {"#1672", "Add terminal color fallbacks", "alice", "updated 12m ago"},
      {"#1668", "Refine table selection state", "maria", "updated 34m ago"},
      {"#1661", "Document line gauge labels", "sam", "updated 1h ago"},
      {"#1658", "Improve calendar event styles", "mei", "updated 2h ago"},
      {"#1649", "Keep layout flex examples in sync", "noah", "updated 4h ago"},
      {"#1637", "Fix canvas label clipping", "ivo", "updated 7h ago"},
      {"#1628", "Add scroll state regression test", "tess", "updated yesterday"}
    ]
  end

  def log_lines(tick, prefix \\ "trace") do
    levels = [
      {"debug", :dark_gray},
      {"info", :cyan},
      {"warn", :yellow},
      {"error", :light_red}
    ]

    for i <- 0..18 do
      {level, color} = Enum.at(levels, rem(tick + i, length(levels)))

      Line.new([
        Span.new(String.pad_leading(to_string(tick + i), 4), fg: :dark_gray),
        Span.new(" #{String.pad_trailing(level, 5)}", fg: color, add_modifier: [:bold]),
        Span.new(" #{prefix}.event.#{rem(tick + i, 7)} "),
        Span.new("rendered frame #{tick + i}", fg: :gray)
      ])
    end
  end

  defp hsv_to_rgb(h, s, v) do
    c = v * s
    x = c * (1 - abs(:math.fmod(h / 60, 2.0) - 1))
    m = v - c

    {r1, g1, b1} =
      cond do
        h < 60 -> {c, x, 0}
        h < 120 -> {x, c, 0}
        h < 180 -> {0, c, x}
        h < 240 -> {0, x, c}
        h < 300 -> {x, 0, c}
        true -> {c, 0, x}
      end

    {round((r1 + m) * 255), round((g1 + m) * 255), round((b1 + m) * 255)}
  end
end

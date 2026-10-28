Code.require_file("support/ratatui_port.exs", __DIR__)

# Markdown viewer: draws a Markdown file (README.md by default) with
# Elui.Widgets.Markdown. The file is parsed once; each frame lays it out
# at the window's width.
#
# Run with:
#
#     mix run examples/markdown.exs [FILE]

defmodule Examples.Markdown do
  @behaviour Elui.App

  alias Elui.{Frame, Layout}
  alias Elui.Widgets.{Block, Markdown}

  @impl true
  def init(_opts) do
    path = List.first(System.argv()) || "README.md"
    blocks = path |> File.read!() |> Elui.Markdown.parse()
    %{path: path, blocks: blocks, scroll: 0, urls: true, size: {80, 24}, lines: nil}
  end

  @impl true
  def update(model, {:resize, width, height}), do: {:ok, clamp(%{model | size: {width, height}})}

  def update(model, event) do
    page = elem(model.size, 1) - 4

    cond do
      Examples.Support.quit?(event) -> :quit
      Examples.Support.key?(event, :down) or char?(event, "j") -> {:ok, scroll(model, 1)}
      Examples.Support.key?(event, :up) or char?(event, "k") -> {:ok, scroll(model, -1)}
      Examples.Support.key?(event, [:page_down, :space]) -> {:ok, scroll(model, page)}
      Examples.Support.key?(event, :page_up) -> {:ok, scroll(model, -page)}
      Examples.Support.key?(event, :home) -> {:ok, %{model | scroll: 0}}
      Examples.Support.key?(event, :end) -> {:ok, scroll(model, :infinity)}
      char?(event, "u") -> {:ok, clamp(%{model | urls: not model.urls})}
      true -> {:ok, model}
    end
  end

  @impl true
  def view(model, frame) do
    [header, body, footer] =
      Layout.vertical([{:length, 1}, {:fill, 1}, {:length, 1}])
      |> Layout.split(Frame.area(frame))

    frame = Examples.Support.render_header(frame, header, "Markdown", model.path)
    frame = Frame.render_widget(frame, widget(model), body)

    Examples.Support.render_footer(
      frame,
      footer,
      "↑/↓ j/k scroll  PgUp/PgDn/Space page  Home/End  u #{if model.urls, do: "hide", else: "show"} URLs  q quit"
    )
  end

  defp widget(model) do
    Markdown.new(model.blocks,
      block: Block.bordered(border_style: [fg: :dark_gray]),
      scroll: model.scroll,
      show_urls: model.urls
    )
  end

  defp char?({:key, {:char, char}, _mods}, char), do: true
  defp char?(_event, _char), do: false

  defp scroll(model, :infinity), do: clamp(%{model | scroll: max_scroll(model)})
  defp scroll(model, delta), do: clamp(%{model | scroll: model.scroll + delta})

  defp clamp(model) do
    model = count_lines(model)
    %{model | scroll: model.scroll |> min(max_scroll(model)) |> max(0)}
  end

  # Counting lays out the whole file, so the count is kept until the width
  # or the URLs change. The body is the window less the header, footer and
  # the block's borders.
  defp count_lines(%{size: {width, _height}, urls: urls} = model) do
    case model.lines do
      {{^width, ^urls}, _count} -> model
      _ -> %{model | lines: {{width, urls}, Markdown.line_count(widget(model), width - 2)}}
    end
  end

  defp max_scroll(%{size: {_width, height}, lines: {_key, count}}), do: count - (height - 4)
end

Examples.Support.run(Examples.Markdown)

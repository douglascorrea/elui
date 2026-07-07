defmodule Elui.Widgets.Tabs do
  @moduledoc """
  A horizontal tab bar with one selected tab. Mirrors ratatui's `Tabs`.

  ## Example

      Tabs.new(["Tab1", "Tab2", "Tab3"],
        selected: 1,
        block: Block.bordered(title: "Tabs"),
        highlight_style: [fg: :yellow]
      )
  """

  alias Elui.Buffer
  alias Elui.Layout.Rect
  alias Elui.Style
  alias Elui.Text.{Line, Span}
  alias Elui.Widgets.Block

  defstruct titles: [],
            selected: 0,
            block: nil,
            style: %Style{},
            highlight_style: Elui.Style.new(add_modifier: [:reversed]),
            divider: "│",
            padding: {" ", " "}

  @type t :: %__MODULE__{}

  @doc """
  Creates a tab bar from titles (strings or lines).

  Options: `:selected` (zero-based), `:block`, `:style`,
  `:highlight_style`, `:divider`, `:padding` (`{left, right}`).
  """
  @spec new([term()], Keyword.t()) :: t()
  def new(titles, opts \\ []) do
    %__MODULE__{
      titles: Enum.map(titles, &Line.to_line/1),
      selected: Keyword.get(opts, :selected, 0),
      block: Keyword.get(opts, :block),
      style: Style.to_style(Keyword.get(opts, :style)),
      highlight_style:
        Style.to_style(
          Keyword.get(opts, :highlight_style, Elui.Style.new(add_modifier: [:reversed]))
        ),
      divider: Keyword.get(opts, :divider, "│"),
      padding: Keyword.get(opts, :padding, {" ", " "})
    }
  end

  @doc "Selects a tab by index."
  @spec select(t(), non_neg_integer()) :: t()
  def select(%__MODULE__{} = tabs, index), do: %{tabs | selected: index}

  @doc false
  def render_into(%__MODULE__{} = tabs, area, buffer) do
    buffer = Buffer.set_style(buffer, area, tabs.style)
    {inner, buffer} = Block.render_with_block(tabs.block, area, buffer)

    if Rect.empty?(inner) or tabs.titles == [] do
      buffer
    else
      {pad_left, pad_right} = tabs.padding
      last = length(tabs.titles) - 1

      {buffer, _x} =
        tabs.titles
        |> Enum.with_index()
        |> Enum.reduce({buffer, inner.x}, fn {title, i}, {buf, x} ->
          max_width = Rect.right(inner) - x

          if max_width <= 0 do
            {buf, x}
          else
            style = if i == tabs.selected, do: tabs.highlight_style, else: tabs.style

            spans =
              [Span.new(pad_left)] ++
                Enum.map(title.spans, &%{&1 | style: Style.patch(style, &1.style)}) ++
                [Span.new(pad_right)]

            line = %Line{spans: spans, style: style}
            {buf, x} = Buffer.set_line(buf, x, inner.y, line, max_width)

            {buf, x} =
              if i < last and Rect.right(inner) - x > 0 do
                Buffer.set_stringn(
                  buf,
                  x,
                  inner.y,
                  tabs.divider,
                  Rect.right(inner) - x,
                  tabs.style
                )
              else
                {buf, x}
              end

            {buf, x}
          end
        end)

      buffer
    end
  end

  defimpl Elui.Widget do
    def render(tabs, area, buffer), do: Elui.Widgets.Tabs.render_into(tabs, area, buffer)
  end
end

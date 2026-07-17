defmodule Elui.Widgets.Block do
  @moduledoc """
  A base widget drawing borders, titles and padding around an area.
  Other widgets typically accept a `:block` option. Mirrors ratatui's
  `Block`.

  ## Example

      Block.new(
        borders: :all,
        border_type: :rounded,
        title: "Status",
        title_bottom: Line.new("q to quit", alignment: :right),
        padding: 1
      )
  """

  alias Elui.Buffer
  alias Elui.Buffer.Cell
  alias Elui.Layout.Rect
  alias Elui.Style
  alias Elui.Symbols.Border
  alias Elui.Text.Line

  defstruct titles_top: [],
            titles_bottom: [],
            borders: [],
            border_type: :plain,
            border_style: %Style{},
            title_style: %Style{},
            style: %Style{},
            padding: [left: 0, right: 0, top: 0, bottom: 0]

  @type border_side :: :top | :bottom | :left | :right
  @type t :: %__MODULE__{}

  @doc """
  Creates a block.

  Options:

    * `:title` - top title (string or `Elui.Text.Line`); can be given
      multiple times via `:titles`
    * `:title_bottom` / `:titles_bottom` - bottom titles
    * `:borders` - `:all`, `:none`, one side, or a list of sides
    * `:border_type` - `:plain`, `:rounded`, `:double`, `:thick`,
      `:quadrant_inside`, `:quadrant_outside`, or a custom
      `%Elui.Symbols.Border{}` set
    * `:border_style`, `:title_style`, `:style` - styles
    * `:padding` - integer, `{horizontal, vertical}` or keyword list
  """
  @spec new(Keyword.t()) :: t()
  def new(opts \\ []) do
    titles_top =
      (List.wrap(Keyword.get(opts, :titles, [])) ++ List.wrap(Keyword.get(opts, :title, [])))
      |> Enum.map(&Line.to_line/1)

    titles_bottom =
      (List.wrap(Keyword.get(opts, :titles_bottom, [])) ++
         List.wrap(Keyword.get(opts, :title_bottom, [])))
      |> Enum.map(&Line.to_line/1)

    %__MODULE__{
      titles_top: titles_top,
      titles_bottom: titles_bottom,
      borders: normalize_borders(Keyword.get(opts, :borders, :none)),
      border_type: Keyword.get(opts, :border_type, :plain),
      border_style: Style.to_style(Keyword.get(opts, :border_style)),
      title_style: Style.to_style(Keyword.get(opts, :title_style)),
      style: Style.to_style(Keyword.get(opts, :style)),
      padding: normalize_padding(Keyword.get(opts, :padding, 0))
    }
  end

  @doc "A block with all borders, equivalent to `new(borders: :all)`."
  @spec bordered(Keyword.t()) :: t()
  def bordered(opts \\ []), do: new(Keyword.put(opts, :borders, :all))

  defp normalize_borders(:all), do: [:top, :bottom, :left, :right]
  defp normalize_borders(:none), do: []
  defp normalize_borders(side) when is_atom(side), do: [side]
  defp normalize_borders(sides) when is_list(sides), do: sides

  defp normalize_padding(p) when is_integer(p), do: [left: p, right: p, top: p, bottom: p]
  defp normalize_padding({h, v}), do: [left: h, right: h, top: v, bottom: v]

  defp normalize_padding(kw) when is_list(kw) do
    [
      left: Keyword.get(kw, :left, 0),
      right: Keyword.get(kw, :right, 0),
      top: Keyword.get(kw, :top, 0),
      bottom: Keyword.get(kw, :bottom, 0)
    ]
  end

  @doc """
  Returns the area inside the block (after borders, titles and
  padding). This is where inner content should be rendered.
  """
  @spec inner(t(), Rect.t()) :: Rect.t()
  def inner(%__MODULE__{} = block, %Rect{} = area) do
    top_border = if :top in block.borders or block.titles_top != [], do: 1, else: 0
    bottom_border = if :bottom in block.borders or block.titles_bottom != [], do: 1, else: 0
    left_border = if :left in block.borders, do: 1, else: 0
    right_border = if :right in block.borders, do: 1, else: 0

    Rect.inner(area,
      left: left_border + block.padding[:left],
      right: right_border + block.padding[:right],
      top: top_border + block.padding[:top],
      bottom: bottom_border + block.padding[:bottom]
    )
  end

  @doc false
  @spec render_into(t(), Rect.t(), Buffer.t()) :: Buffer.t()
  def render_into(%__MODULE__{} = block, %Rect{} = area, %Buffer{} = buffer) do
    if Rect.empty?(area) do
      buffer
    else
      symbols = Border.set(block.border_type)

      buffer
      |> Buffer.set_style(area, block.style)
      |> draw_borders(block, area, symbols)
      |> draw_titles(block, area)
    end
  end

  defp draw_borders(buffer, block, area, sym) do
    left = area.x
    right = Rect.right(area) - 1
    top = area.y
    bottom = Rect.bottom(area) - 1
    style = block.border_style

    buffer =
      if :top in block.borders do
        Enum.reduce(left..right, buffer, fn x, buf ->
          put_symbol(buf, x, top, sym.horizontal_top, style)
        end)
      else
        buffer
      end

    buffer =
      if :bottom in block.borders and bottom > top do
        Enum.reduce(left..right, buffer, fn x, buf ->
          put_symbol(buf, x, bottom, sym.horizontal_bottom, style)
        end)
      else
        buffer
      end

    buffer =
      if :left in block.borders do
        Enum.reduce(top..bottom, buffer, fn y, buf ->
          put_symbol(buf, left, y, sym.vertical_left, style)
        end)
      else
        buffer
      end

    buffer =
      if :right in block.borders and right > left do
        Enum.reduce(top..bottom, buffer, fn y, buf ->
          put_symbol(buf, right, y, sym.vertical_right, style)
        end)
      else
        buffer
      end

    buffer
    |> maybe_corner(
      :top in block.borders and :left in block.borders,
      left,
      top,
      sym.top_left,
      style
    )
    |> maybe_corner(
      :top in block.borders and :right in block.borders,
      right,
      top,
      sym.top_right,
      style
    )
    |> maybe_corner(
      :bottom in block.borders and :left in block.borders,
      left,
      bottom,
      sym.bottom_left,
      style
    )
    |> maybe_corner(
      :bottom in block.borders and :right in block.borders,
      right,
      bottom,
      sym.bottom_right,
      style
    )
  end

  defp maybe_corner(buffer, false, _x, _y, _symbol, _style), do: buffer

  defp maybe_corner(buffer, true, x, y, symbol, style) do
    put_symbol(buffer, x, y, symbol, style)
  end

  defp put_symbol(buffer, x, y, symbol, style) do
    cell =
      buffer
      |> Buffer.get(x, y)
      |> Cell.set_symbol(symbol)
      |> Cell.set_style(style)
      |> Map.put(:skip, false)

    Buffer.put(buffer, x, y, cell)
  end

  defp draw_titles(buffer, block, area) do
    title_area_x = area.x + if(:left in block.borders, do: 1, else: 0)
    title_width = area.width - borders_width(block)

    buffer =
      Enum.reduce(block.titles_top, buffer, fn title, buf ->
        title =
          Line.patch_style(%{title | style: Style.patch(block.title_style, title.style)}, [])

        {buf, _} = Buffer.set_line(buf, title_area_x, area.y, title, title_width)
        buf
      end)

    bottom_y = Rect.bottom(area) - 1

    Enum.reduce(block.titles_bottom, buffer, fn title, buf ->
      title = Line.patch_style(%{title | style: Style.patch(block.title_style, title.style)}, [])
      {buf, _} = Buffer.set_line(buf, title_area_x, bottom_y, title, title_width)
      buf
    end)
  end

  defp borders_width(block) do
    left = if :left in block.borders, do: 1, else: 0
    right = if :right in block.borders, do: 1, else: 0
    left + right
  end

  @doc false
  @spec render_with_block(t() | nil, Rect.t(), Buffer.t()) :: {Rect.t(), Buffer.t()}
  def render_with_block(nil, area, buffer), do: {area, buffer}

  def render_with_block(%__MODULE__{} = block, area, buffer) do
    buffer = render_into(block, area, buffer)
    {inner(block, area), buffer}
  end

  defimpl Elui.Widget do
    def render(block, area, buffer), do: Elui.Widgets.Block.render_into(block, area, buffer)
  end
end

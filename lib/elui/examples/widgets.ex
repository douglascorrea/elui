defmodule Elui.Examples.Widgets.Button do
  @moduledoc false

  alias Elui.Buffer
  alias Elui.Buffer.Cell
  alias Elui.Layout.Rect
  alias Elui.Style
  alias Elui.Text.Width
  alias Elui.Widgets.Block

  defstruct label: "",
            fg: :white,
            bg: :blue,
            selected: false,
            pressed: false

  def new(label, opts \\ []) do
    %__MODULE__{
      label: label,
      fg: Keyword.get(opts, :fg, :white),
      bg: Keyword.get(opts, :bg, :blue),
      selected: Keyword.get(opts, :selected, false),
      pressed: Keyword.get(opts, :pressed, false)
    }
  end

  def render_into(%__MODULE__{} = button, area, buffer) do
    base =
      Style.new(
        fg: button.fg,
        bg: button.bg,
        add_modifier: if(button.pressed, do: [:bold, :reversed], else: [:bold])
      )

    border = if button.selected, do: :double, else: :rounded

    block =
      Block.bordered(
        border_type: border,
        border_style: Style.patch(base, if(button.selected, do: [fg: :white], else: [])),
        style: base
      )

    buffer = Block.render_into(block, area, buffer)
    inner = Block.inner(block, area)

    buffer =
      Enum.reduce(Rect.positions(inner), buffer, fn {x, y}, buf ->
        Buffer.put(buf, x, y, Cell.new(" ", base))
      end)

    label =
      if button.pressed do
        "[ #{button.label} ]"
      else
        "  #{button.label}  "
      end

    x = inner.x + max(div(inner.width - Width.of(label), 2), 0)
    y = inner.y + div(inner.height, 2)
    Buffer.set_string(buffer, x, y, label, base)
  end

  defimpl Elui.Widget do
    def render(button, area, buffer),
      do: Elui.Examples.Widgets.Button.render_into(button, area, buffer)
  end
end

defmodule Elui.Examples.Widgets.MetricTile do
  @moduledoc false

  alias Elui.Buffer
  alias Elui.Buffer.Cell
  alias Elui.Layout.Rect
  alias Elui.Text.Line
  alias Elui.Widgets.Block

  defstruct title: "",
            value: "",
            ratio: 0.0,
            color: :cyan

  def new(title, value, ratio, opts \\ []) do
    %__MODULE__{
      title: title,
      value: value,
      ratio: ratio |> max(0.0) |> min(1.0),
      color: Keyword.get(opts, :color, :cyan)
    }
  end

  def render_into(%__MODULE__{} = tile, area, buffer) do
    block =
      Block.bordered(
        title: Line.new(tile.title, style: [fg: tile.color, add_modifier: [:bold]]),
        border_style: [fg: tile.color]
      )

    buffer = Block.render_into(block, area, buffer)
    inner = Block.inner(block, area)

    if Rect.empty?(inner) do
      buffer
    else
      value = Line.new(tile.value, style: [fg: :white, add_modifier: [:bold]], alignment: :center)
      {buffer, _} = Buffer.set_line(buffer, inner.x, inner.y, value, inner.width)

      bar_width = round(inner.width * tile.ratio)

      Enum.reduce(0..(inner.width - 1)//1, buffer, fn dx, buf ->
        symbol = if dx < bar_width, do: "█", else: "░"
        style = if dx < bar_width, do: [fg: tile.color], else: [fg: :dark_gray]
        Buffer.put(buf, inner.x + dx, Rect.bottom(inner) - 1, Cell.new(symbol, style))
      end)
    end
  end

  defimpl Elui.Widget do
    def render(tile, area, buffer),
      do: Elui.Examples.Widgets.MetricTile.render_into(tile, area, buffer)
  end
end

defmodule Elui.Examples.Widgets.Hyperlink do
  @moduledoc false

  alias Elui.Buffer
  alias Elui.Buffer.Cell
  alias Elui.Style
  alias Elui.Text.Width

  defstruct text: "", url: ""

  def new(text, url), do: %__MODULE__{text: text, url: url}

  def render_into(%__MODULE__{} = link, area, buffer) do
    if area.width == 0 or area.height == 0 do
      buffer
    else
      text = "\e]8;;#{link.url}\a#{link.text}\e]8;;\a"
      x = area.x + max(div(area.width - Width.of(link.text), 2), 0)
      y = area.y + div(area.height, 2)
      Buffer.put(buffer, x, y, Cell.new(text, Style.new(fg: :cyan, add_modifier: [:underlined])))
    end
  end

  defimpl Elui.Widget do
    def render(link, area, buffer),
      do: Elui.Examples.Widgets.Hyperlink.render_into(link, area, buffer)
  end
end

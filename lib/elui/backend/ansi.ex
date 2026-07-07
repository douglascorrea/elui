defmodule Elui.Backend.Ansi do
  @moduledoc """
  A terminal backend that writes ANSI/VT100 escape sequences to
  stdout. This is the backend used for real terminal applications
  (the equivalent of ratatui's crossterm/termion backends).

  Supports the alternate screen, truecolor/256/16-color output,
  text modifiers and cursor control.
  """

  @behaviour Elui.Backend

  alias Elui.Style
  alias Elui.Style.Color

  defstruct alternate_screen: true, device: :stdio

  @impl true
  def init(opts \\ []) do
    state = %__MODULE__{
      alternate_screen: Keyword.get(opts, :alternate_screen, true),
      device: Keyword.get(opts, :device, :stdio)
    }

    if state.alternate_screen do
      write(state, "\e[?1049h")
    end

    write(state, "\e[2J\e[H")
    state
  end

  @impl true
  def draw(state, updates) do
    output =
      updates
      |> Enum.map_join(fn {x, y, cell} ->
        [move_to(x, y), sgr(cell.style), cell.symbol]
      end)

    write(state, [output, "\e[0m"])
    state
  end

  @impl true
  def hide_cursor(state), do: write(state, "\e[?25l")

  @impl true
  def show_cursor(state), do: write(state, "\e[?25h")

  @impl true
  def set_cursor_position(state, {x, y}), do: write(state, move_to(x, y))

  @impl true
  def clear(state), do: write(state, "\e[2J\e[H")

  @impl true
  def size(_state) do
    with {:ok, columns} <- :io.columns(),
         {:ok, rows} <- :io.rows() do
      {columns, rows}
    else
      _ -> {80, 24}
    end
  end

  @impl true
  def flush(state), do: state

  @impl true
  def restore(state) do
    write(state, "\e[0m\e[?25h")

    if state.alternate_screen do
      write(state, "\e[?1049l")
    end

    state
  end

  defp write(state, data) do
    IO.write(state.device, data)
    state
  end

  defp move_to(x, y), do: "\e[#{y + 1};#{x + 1}H"

  @doc false
  @spec sgr(Style.t()) :: String.t()
  def sgr(%Style{} = style) do
    codes =
      [0] ++
        modifier_codes(style.add_modifier) ++
        color_codes(style.fg, :fg) ++
        color_codes(style.bg, :bg)

    "\e[#{Enum.join(codes, ";")}m"
  end

  defp color_codes(nil, _), do: []
  defp color_codes(color, :fg), do: Color.fg_codes(color)
  defp color_codes(color, :bg), do: Color.bg_codes(color)

  @modifier_code %{
    bold: 1,
    dim: 2,
    italic: 3,
    underlined: 4,
    slow_blink: 5,
    rapid_blink: 6,
    reversed: 7,
    hidden: 8,
    crossed_out: 9
  }

  defp modifier_codes(modifiers) do
    modifiers |> Enum.map(&Map.fetch!(@modifier_code, &1)) |> Enum.sort()
  end
end

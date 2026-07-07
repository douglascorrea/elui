defmodule Elui.Symbols do
  @moduledoc """
  Unicode symbol sets used to draw lines, borders, bars, blocks,
  braille patterns, shades and scrollbars. Mirrors ratatui's `symbols`
  module.
  """

  defmodule Line do
    @moduledoc "Box drawing line symbol sets."

    defstruct vertical: "│",
              horizontal: "─",
              top_left: "┌",
              top_right: "┐",
              bottom_left: "└",
              bottom_right: "┘",
              vertical_left: "┤",
              vertical_right: "├",
              horizontal_down: "┬",
              horizontal_up: "┴",
              cross: "┼"

    @type t :: %__MODULE__{}

    def normal, do: %__MODULE__{}

    def rounded do
      %__MODULE__{top_left: "╭", top_right: "╮", bottom_left: "╰", bottom_right: "╯"}
    end

    def double do
      %__MODULE__{
        vertical: "║",
        horizontal: "═",
        top_left: "╔",
        top_right: "╗",
        bottom_left: "╚",
        bottom_right: "╝",
        vertical_left: "╣",
        vertical_right: "╠",
        horizontal_down: "╦",
        horizontal_up: "╩",
        cross: "╬"
      }
    end

    def thick do
      %__MODULE__{
        vertical: "┃",
        horizontal: "━",
        top_left: "┏",
        top_right: "┓",
        bottom_left: "┗",
        bottom_right: "┛",
        vertical_left: "┫",
        vertical_right: "┣",
        horizontal_down: "┳",
        horizontal_up: "┻",
        cross: "╋"
      }
    end
  end

  defmodule Border do
    @moduledoc "Border symbol sets used by `Elui.Widgets.Block`."

    defstruct top_left: "┌",
              top_right: "┐",
              bottom_left: "└",
              bottom_right: "┘",
              vertical_left: "│",
              vertical_right: "│",
              horizontal_top: "─",
              horizontal_bottom: "─"

    @type t :: %__MODULE__{}

    def plain, do: %__MODULE__{}

    def rounded do
      %__MODULE__{top_left: "╭", top_right: "╮", bottom_left: "╰", bottom_right: "╯"}
    end

    def double do
      %__MODULE__{
        top_left: "╔",
        top_right: "╗",
        bottom_left: "╚",
        bottom_right: "╝",
        vertical_left: "║",
        vertical_right: "║",
        horizontal_top: "═",
        horizontal_bottom: "═"
      }
    end

    def thick do
      %__MODULE__{
        top_left: "┏",
        top_right: "┓",
        bottom_left: "┗",
        bottom_right: "┛",
        vertical_left: "┃",
        vertical_right: "┃",
        horizontal_top: "━",
        horizontal_bottom: "━"
      }
    end

    def quadrant_outside do
      %__MODULE__{
        top_left: "▛",
        top_right: "▜",
        bottom_left: "▙",
        bottom_right: "▟",
        vertical_left: "▌",
        vertical_right: "▐",
        horizontal_top: "▀",
        horizontal_bottom: "▄"
      }
    end

    def quadrant_inside do
      %__MODULE__{
        top_left: "▗",
        top_right: "▖",
        bottom_left: "▝",
        bottom_right: "▘",
        vertical_left: "▐",
        vertical_right: "▌",
        horizontal_top: "▄",
        horizontal_bottom: "▀"
      }
    end

    def full do
      %__MODULE__{
        top_left: "█",
        top_right: "█",
        bottom_left: "█",
        bottom_right: "█",
        vertical_left: "█",
        vertical_right: "█",
        horizontal_top: "█",
        horizontal_bottom: "█"
      }
    end

    def empty do
      %__MODULE__{
        top_left: " ",
        top_right: " ",
        bottom_left: " ",
        bottom_right: " ",
        vertical_left: " ",
        vertical_right: " ",
        horizontal_top: " ",
        horizontal_bottom: " "
      }
    end

    @doc "Returns a border set by name."
    @spec set(atom() | t()) :: t()
    def set(%__MODULE__{} = custom), do: custom
    def set(:plain), do: plain()
    def set(:rounded), do: rounded()
    def set(:double), do: double()
    def set(:thick), do: thick()
    def set(:quadrant_outside), do: quadrant_outside()
    def set(:quadrant_inside), do: quadrant_inside()
    def set(:full), do: full()
    def set(:empty), do: empty()
  end

  defmodule Bar do
    @moduledoc "Vertical bar symbols in eighth increments (bottom up)."

    def full, do: "█"
    def seven_eighths, do: "▇"
    def three_quarters, do: "▆"
    def five_eighths, do: "▅"
    def half, do: "▄"
    def three_eighths, do: "▃"
    def one_quarter, do: "▂"
    def one_eighth, do: "▁"
    def empty, do: " "

    @doc "Nine-level bar set, indexed 0 (empty) to 8 (full)."
    def nine_levels, do: [" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

    @doc "Three-level bar set: empty, half, full."
    def three_levels, do: [" ", "▄", "█"]
  end

  defmodule Block do
    @moduledoc "Horizontal block symbols in eighth increments (left to right)."

    def full, do: "█"
    def seven_eighths, do: "▉"
    def three_quarters, do: "▊"
    def five_eighths, do: "▋"
    def half, do: "▌"
    def three_eighths, do: "▍"
    def one_quarter, do: "▎"
    def one_eighth, do: "▏"
    def empty, do: " "

    @doc "Nine-level block set, indexed 0 (empty) to 8 (full)."
    def nine_levels, do: [" ", "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█"]

    @doc "Three-level block set: empty, half, full."
    def three_levels, do: [" ", "▌", "█"]
  end

  defmodule Shade do
    @moduledoc "Shade symbols."

    def empty, do: " "
    def light, do: "░"
    def medium, do: "▒"
    def dark, do: "▓"
    def full, do: "█"
  end

  defmodule Scrollbar do
    @moduledoc "Scrollbar symbol sets."

    defstruct track: "│", thumb: "█", begin: "↑", end: "↓"

    @type t :: %__MODULE__{}

    def vertical, do: %__MODULE__{track: "│", thumb: "█", begin: "↑", end: "↓"}
    def horizontal, do: %__MODULE__{track: "─", thumb: "█", begin: "←", end: "→"}
    def double_vertical, do: %__MODULE__{track: "║", thumb: "█", begin: "▲", end: "▼"}
    def double_horizontal, do: %__MODULE__{track: "═", thumb: "█", begin: "◄", end: "►"}
  end

  defmodule Braille do
    @moduledoc """
    Braille pattern symbols. A braille cell is a 2x4 dot grid; the
    codepoint is `0x2800` plus a bitmask of raised dots.
    """

    @blank 0x2800

    # Dot bit values by {x, y} within the 2x4 braille cell.
    @dots %{
      {0, 0} => 0x01,
      {0, 1} => 0x02,
      {0, 2} => 0x04,
      {0, 3} => 0x40,
      {1, 0} => 0x08,
      {1, 1} => 0x10,
      {1, 2} => 0x20,
      {1, 3} => 0x80
    }

    @doc "The blank braille codepoint."
    def blank, do: @blank

    @doc "The bit value for the dot at `{x, y}` (x in 0..1, y in 0..3)."
    def dot(x, y), do: Map.fetch!(@dots, {x, y})

    @doc "Converts a dot bitmask into the corresponding braille character."
    def char(mask), do: <<@blank + mask::utf8>>
  end

  @doc """
  Marker types used by `Elui.Widgets.Canvas` and `Elui.Widgets.Chart`:
  `:dot`, `:block`, `:bar`, `:braille`, `:half_block` or `{:custom, char}`.
  """
  @type marker :: :dot | :block | :bar | :braille | :half_block | {:custom, String.t()}

  def marker_symbol(:dot), do: "•"
  def marker_symbol(:block), do: "█"
  def marker_symbol(:bar), do: "▄"
  def marker_symbol(:half_block), do: "█"
  def marker_symbol({:custom, char}), do: char
end

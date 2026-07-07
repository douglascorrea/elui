defmodule Elui.Style do
  @moduledoc """
  Styling of terminal cells: foreground/background colors and text
  modifiers. Mirrors ratatui's `Style` and `Modifier`.

  Styles compose with `patch/2`: values set in the second style win,
  and unset (`nil`) values fall through, exactly like ratatui's
  `Style::patch`.

  ## Example

      Elui.Style.new(fg: :yellow, add_modifier: [:bold])
      Elui.Style.new() |> Elui.Style.fg(:red) |> Elui.Style.bg(:black)
  """

  alias Elui.Style.Color

  defstruct fg: nil,
            bg: nil,
            underline_color: nil,
            add_modifier: MapSet.new(),
            sub_modifier: MapSet.new()

  @modifiers ~w(bold dim italic underlined slow_blink rapid_blink reversed hidden crossed_out)a

  @type modifier ::
          :bold
          | :dim
          | :italic
          | :underlined
          | :slow_blink
          | :rapid_blink
          | :reversed
          | :hidden
          | :crossed_out

  @type t :: %__MODULE__{
          fg: Color.t() | nil,
          bg: Color.t() | nil,
          underline_color: Color.t() | nil,
          add_modifier: MapSet.t(modifier()),
          sub_modifier: MapSet.t(modifier())
        }

  @doc "The list of all supported modifiers."
  @spec modifiers() :: [modifier()]
  def modifiers, do: @modifiers

  @doc """
  Creates a new style.

  Options: `:fg`, `:bg`, `:underline_color`, `:add_modifier` and
  `:sub_modifier` (lists of modifier atoms).
  """
  @spec new(Keyword.t()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      fg: Keyword.get(opts, :fg),
      bg: Keyword.get(opts, :bg),
      underline_color: Keyword.get(opts, :underline_color),
      add_modifier: MapSet.new(Keyword.get(opts, :add_modifier, [])),
      sub_modifier: MapSet.new(Keyword.get(opts, :sub_modifier, []))
    }
  end

  @doc "A style that resets every attribute to the terminal defaults."
  @spec reset() :: t()
  def reset do
    %__MODULE__{
      fg: :reset,
      bg: :reset,
      underline_color: :reset,
      add_modifier: MapSet.new(),
      sub_modifier: MapSet.new(@modifiers)
    }
  end

  @spec fg(t(), Color.t()) :: t()
  def fg(%__MODULE__{} = style, color), do: %{style | fg: color}

  @spec bg(t(), Color.t()) :: t()
  def bg(%__MODULE__{} = style, color), do: %{style | bg: color}

  @spec underline_color(t(), Color.t()) :: t()
  def underline_color(%__MODULE__{} = style, color), do: %{style | underline_color: color}

  @doc "Adds one or more modifiers to the style."
  @spec add_modifier(t(), modifier() | [modifier()]) :: t()
  def add_modifier(%__MODULE__{} = style, mods) do
    mods = List.wrap(mods)

    %{
      style
      | add_modifier: MapSet.union(style.add_modifier, MapSet.new(mods)),
        sub_modifier: MapSet.difference(style.sub_modifier, MapSet.new(mods))
    }
  end

  @doc "Removes one or more modifiers from the style."
  @spec remove_modifier(t(), modifier() | [modifier()]) :: t()
  def remove_modifier(%__MODULE__{} = style, mods) do
    mods = List.wrap(mods)

    %{
      style
      | sub_modifier: MapSet.union(style.sub_modifier, MapSet.new(mods)),
        add_modifier: MapSet.difference(style.add_modifier, MapSet.new(mods))
    }
  end

  for mod <- @modifiers do
    @doc "Adds the `#{mod}` modifier."
    @spec unquote(mod)(t()) :: t()
    def unquote(mod)(%__MODULE__{} = style), do: add_modifier(style, unquote(mod))
  end

  @doc """
  Combines two styles. Attributes from `other` override `style`; unset
  attributes fall through.
  """
  @spec patch(t(), t() | Keyword.t() | nil) :: t()
  def patch(%__MODULE__{} = style, nil), do: style
  def patch(%__MODULE__{} = style, opts) when is_list(opts), do: patch(style, new(opts))

  def patch(%__MODULE__{} = style, %__MODULE__{} = other) do
    %__MODULE__{
      fg: other.fg || style.fg,
      bg: other.bg || style.bg,
      underline_color: other.underline_color || style.underline_color,
      add_modifier:
        style.add_modifier
        |> MapSet.difference(other.sub_modifier)
        |> MapSet.union(other.add_modifier),
      sub_modifier:
        style.sub_modifier
        |> MapSet.difference(other.add_modifier)
        |> MapSet.union(other.sub_modifier)
    }
  end

  @doc "Coerces keyword lists or nil into a `%Elui.Style{}`."
  @spec to_style(t() | Keyword.t() | nil) :: t()
  def to_style(nil), do: new()
  def to_style(%__MODULE__{} = style), do: style
  def to_style(opts) when is_list(opts), do: new(opts)
end

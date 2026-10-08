defmodule Elui.Theme do
  @moduledoc """
  Named semantic color palettes for Elui apps.

  A theme maps roles (`:fg`, `:bg`, `:muted`, `:border`, `:title`,
  `:highlight`, `:accent`, `:danger`, `:success`, `:warning`) to
  `Elui.Style` values. Built-ins include accessible baseline palettes and
  colorful truecolor palettes for modern terminals.
  """

  alias Elui.Style

  defstruct name: nil, roles: %{}

  @type role ::
          :fg
          | :bg
          | :muted
          | :border
          | :title
          | :highlight
          | :accent
          | :danger
          | :success
          | :warning

  @type t :: %__MODULE__{
          name: String.t(),
          roles: %{optional(role()) => Style.t()}
        }

  @names ~w(dark light high-contrast opencode tokyonight catppuccin)
  @default_name "dark"

  @roles ~w(fg bg muted border title highlight accent danger success warning)a

  @doc "Built-in theme names in display order."
  @spec names() :: [String.t()]
  def names, do: @names

  @doc "Default theme name (`dark`)."
  @spec default_name() :: String.t()
  def default_name, do: @default_name

  @doc "Semantic roles every built-in theme defines."
  @spec roles() :: [role()]
  def roles, do: @roles

  @doc """
  Looks up a built-in theme by name.

  Returns `{:ok, theme}` or `:error` when the name is unknown.
  """
  @spec get(String.t()) :: {:ok, t()} | :error
  def get(name) when is_binary(name) do
    case name do
      "dark" -> {:ok, dark()}
      "light" -> {:ok, light()}
      "high-contrast" -> {:ok, high_contrast()}
      "opencode" -> {:ok, opencode()}
      "tokyonight" -> {:ok, tokyonight()}
      "catppuccin" -> {:ok, catppuccin()}
      _ -> :error
    end
  end

  @doc "Like `get/1` but raises on an unknown name."
  @spec get!(String.t()) :: t()
  def get!(name) when is_binary(name) do
    case get(name) do
      {:ok, theme} -> theme
      :error -> raise ArgumentError, "unknown Elui theme: #{inspect(name)}"
    end
  end

  @doc "The default built-in theme."
  @spec default() :: t()
  def default, do: get!(@default_name)

  @doc "Returns the `Elui.Style` for a semantic role."
  @spec style(t(), role()) :: Style.t()
  def style(%__MODULE__{roles: roles}, role) when role in @roles do
    Map.fetch!(roles, role)
  end

  @doc "Keyword options suitable for widget style fields for a role."
  @spec opts(t(), role()) :: Keyword.t()
  def opts(%__MODULE__{} = theme, role) do
    style = style(theme, role)

    []
    |> maybe_put(:fg, style.fg)
    |> maybe_put(:bg, style.bg)
    |> maybe_put(:underline_color, style.underline_color)
    |> maybe_put(:add_modifier, MapSet.to_list(style.add_modifier))
  end

  @doc "Dark theme (default)."
  @spec dark() :: t()
  def dark do
    build("dark", %{
      fg: [fg: :white],
      bg: [bg: :black],
      muted: [fg: :dark_gray],
      border: [fg: :dark_gray],
      title: [fg: :cyan, add_modifier: [:bold]],
      highlight: [fg: :black, bg: :blue, add_modifier: [:bold]],
      accent: [fg: :yellow, add_modifier: [:bold]],
      danger: [fg: :light_red],
      success: [fg: :light_green],
      warning: [fg: :light_yellow]
    })
  end

  @doc "Light theme."
  @spec light() :: t()
  def light do
    build("light", %{
      fg: [fg: :black],
      bg: [bg: :white],
      muted: [fg: :gray],
      border: [fg: :gray],
      title: [fg: :blue, add_modifier: [:bold]],
      highlight: [fg: :white, bg: :blue, add_modifier: [:bold]],
      accent: [fg: :magenta, add_modifier: [:bold]],
      danger: [fg: :red],
      success: [fg: :green],
      warning: [fg: :yellow]
    })
  end

  @doc "High-contrast theme for accessibility."
  @spec high_contrast() :: t()
  def high_contrast do
    build("high-contrast", %{
      fg: [fg: :white, add_modifier: [:bold]],
      bg: [bg: :black],
      muted: [fg: :white],
      border: [fg: :white],
      title: [fg: :white, add_modifier: [:bold, :underlined]],
      highlight: [fg: :black, bg: :white, add_modifier: [:bold]],
      accent: [fg: :light_yellow, add_modifier: [:bold]],
      danger: [fg: :light_red, add_modifier: [:bold]],
      success: [fg: :light_green, add_modifier: [:bold]],
      warning: [fg: :light_yellow, add_modifier: [:bold]]
    })
  end

  @doc "OpenCode-inspired warm orange, blue, and purple truecolor theme."
  @spec opencode() :: t()
  def opencode do
    build("opencode", %{
      fg: [fg: {:rgb, 238, 238, 238}],
      bg: [bg: {:rgb, 10, 10, 10}],
      muted: [fg: {:rgb, 128, 128, 128}],
      border: [fg: {:rgb, 72, 72, 72}],
      title: [fg: {:rgb, 250, 178, 131}, add_modifier: [:bold]],
      highlight: [fg: {:rgb, 10, 10, 10}, bg: {:rgb, 250, 178, 131}, add_modifier: [:bold]],
      accent: [fg: {:rgb, 157, 124, 216}, add_modifier: [:bold]],
      danger: [fg: {:rgb, 224, 108, 117}],
      success: [fg: {:rgb, 127, 216, 143}],
      warning: [fg: {:rgb, 245, 167, 66}]
    })
  end

  @doc "Tokyo Night-inspired blue, purple, and coral truecolor theme."
  @spec tokyonight() :: t()
  def tokyonight do
    build("tokyonight", %{
      fg: [fg: {:rgb, 200, 211, 245}],
      bg: [bg: {:rgb, 26, 27, 38}],
      muted: [fg: {:rgb, 130, 139, 184}],
      border: [fg: {:rgb, 115, 122, 162}],
      title: [fg: {:rgb, 192, 153, 255}, add_modifier: [:bold]],
      highlight: [fg: {:rgb, 26, 27, 38}, bg: {:rgb, 130, 170, 255}, add_modifier: [:bold]],
      accent: [fg: {:rgb, 255, 150, 108}, add_modifier: [:bold]],
      danger: [fg: {:rgb, 255, 117, 127}],
      success: [fg: {:rgb, 195, 232, 141}],
      warning: [fg: {:rgb, 255, 199, 119}]
    })
  end

  @doc "Catppuccin Mocha-inspired mauve, pink, and blue truecolor theme."
  @spec catppuccin() :: t()
  def catppuccin do
    build("catppuccin", %{
      fg: [fg: {:rgb, 205, 214, 244}],
      bg: [bg: {:rgb, 30, 30, 46}],
      muted: [fg: {:rgb, 147, 153, 178}],
      border: [fg: {:rgb, 88, 91, 112}],
      title: [fg: {:rgb, 203, 166, 247}, add_modifier: [:bold]],
      highlight: [fg: {:rgb, 30, 30, 46}, bg: {:rgb, 137, 180, 250}, add_modifier: [:bold]],
      accent: [fg: {:rgb, 245, 194, 231}, add_modifier: [:bold]],
      danger: [fg: {:rgb, 243, 139, 168}],
      success: [fg: {:rgb, 166, 227, 161}],
      warning: [fg: {:rgb, 249, 226, 175}]
    })
  end

  defp build(name, role_opts) do
    roles =
      Map.new(role_opts, fn {role, opts} ->
        {role, Style.new(opts)}
      end)

    missing = @roles -- Map.keys(roles)

    if missing != [] do
      raise ArgumentError, "theme #{name} missing roles: #{inspect(missing)}"
    end

    %__MODULE__{name: name, roles: roles}
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, []), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end

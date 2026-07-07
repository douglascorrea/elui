defmodule Elui.Style.Color do
  @moduledoc """
  Terminal colors, mirroring ratatui's `Color`.

  A color is one of:

    * `:reset` - the terminal's default color
    * a named ANSI color atom: `:black`, `:red`, `:green`, `:yellow`,
      `:blue`, `:magenta`, `:cyan`, `:gray`, `:dark_gray`, `:light_red`,
      `:light_green`, `:light_yellow`, `:light_blue`, `:light_magenta`,
      `:light_cyan`, `:white`
    * `{:rgb, r, g, b}` - a 24-bit truecolor value
    * `{:indexed, n}` - one of the 256 indexed terminal colors
  """

  @type t ::
          :reset
          | :black
          | :red
          | :green
          | :yellow
          | :blue
          | :magenta
          | :cyan
          | :gray
          | :dark_gray
          | :light_red
          | :light_green
          | :light_yellow
          | :light_blue
          | :light_magenta
          | :light_cyan
          | :white
          | {:rgb, 0..255, 0..255, 0..255}
          | {:indexed, 0..255}

  @named ~w(
    black red green yellow blue magenta cyan gray dark_gray
    light_red light_green light_yellow light_blue light_magenta
    light_cyan white
  )a

  @doc "Builds an RGB color."
  @spec rgb(0..255, 0..255, 0..255) :: t()
  def rgb(r, g, b), do: {:rgb, r, g, b}

  @doc "Builds an indexed (0-255) color."
  @spec indexed(0..255) :: t()
  def indexed(n), do: {:indexed, n}

  @doc ~S"""
  Parses a color from a string: a named color (`"red"`, `"lightblue"`),
  an index (`"42"`) or a hex code (`"#ff00ff"`).

      iex> Elui.Style.Color.from_string("#FF0000")
      {:ok, {:rgb, 255, 0, 0}}
  """
  @spec from_string(String.t()) :: {:ok, t()} | :error
  def from_string(str) when is_binary(str) do
    normalized = str |> String.downcase() |> String.replace(["-", "_", " "], "")

    cond do
      normalized == "reset" ->
        {:ok, :reset}

      (color = parse_named(normalized)) != nil ->
        {:ok, color}

      String.starts_with?(normalized, "#") and byte_size(normalized) == 7 ->
        with {:ok, <<r, g, b>>} <- Base.decode16(String.slice(normalized, 1..6), case: :mixed) do
          {:ok, {:rgb, r, g, b}}
        end

      Regex.match?(~r/^\d+$/, normalized) ->
        case String.to_integer(normalized) do
          n when n in 0..255 -> {:ok, {:indexed, n}}
          _ -> :error
        end

      true ->
        :error
    end
  end

  defp parse_named(str) do
    Enum.find(@named, fn atom ->
      Atom.to_string(atom) |> String.replace("_", "") == str
    end)
  end

  @doc "Returns the ANSI SGR codes for the color as a foreground color."
  @spec fg_codes(t()) :: [non_neg_integer()]
  def fg_codes(color), do: codes(color, 30, 38, 39)

  @doc "Returns the ANSI SGR codes for the color as a background color."
  @spec bg_codes(t()) :: [non_neg_integer()]
  def bg_codes(color), do: codes(color, 40, 48, 49)

  defp codes(:reset, _base, _ext, default), do: [default]
  defp codes(:black, base, _ext, _d), do: [base]
  defp codes(:red, base, _ext, _d), do: [base + 1]
  defp codes(:green, base, _ext, _d), do: [base + 2]
  defp codes(:yellow, base, _ext, _d), do: [base + 3]
  defp codes(:blue, base, _ext, _d), do: [base + 4]
  defp codes(:magenta, base, _ext, _d), do: [base + 5]
  defp codes(:cyan, base, _ext, _d), do: [base + 6]
  defp codes(:gray, base, _ext, _d), do: [base + 7]
  defp codes(:dark_gray, base, _ext, _d), do: [base + 60]
  defp codes(:light_red, base, _ext, _d), do: [base + 61]
  defp codes(:light_green, base, _ext, _d), do: [base + 62]
  defp codes(:light_yellow, base, _ext, _d), do: [base + 63]
  defp codes(:light_blue, base, _ext, _d), do: [base + 64]
  defp codes(:light_magenta, base, _ext, _d), do: [base + 65]
  defp codes(:light_cyan, base, _ext, _d), do: [base + 66]
  defp codes(:white, base, _ext, _d), do: [base + 67]
  defp codes({:indexed, n}, _base, ext, _d), do: [ext, 5, n]
  defp codes({:rgb, r, g, b}, _base, ext, _d), do: [ext, 2, r, g, b]
end

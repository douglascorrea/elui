defmodule Elui.Text.Width do
  @moduledoc """
  Display width calculation for terminal cells.

  Handles common wide (East Asian) character ranges and zero-width
  characters. This is a pragmatic approximation of the Unicode
  east-asian-width tables used by ratatui.
  """

  @doc "The display width of a string in terminal cells."
  @spec of(String.t()) :: non_neg_integer()
  def of(string) when is_binary(string) do
    string
    |> String.graphemes()
    |> Enum.reduce(0, fn g, acc -> acc + grapheme_width(g) end)
  end

  @doc "The display width of a single grapheme."
  @spec grapheme_width(String.t()) :: non_neg_integer()
  def grapheme_width(grapheme) do
    case String.to_charlist(grapheme) do
      [] -> 0
      [cp | _] -> char_width(cp)
    end
  end

  defp char_width(cp) when cp < 32, do: 0
  defp char_width(cp) when cp in 0x0300..0x036F, do: 0
  defp char_width(cp) when cp == 0x200B, do: 0

  defp char_width(cp)
       when cp in 0x1100..0x115F or
              cp in 0x2E80..0x303E or
              cp in 0x3041..0x33FF or
              cp in 0x3400..0x4DBF or
              cp in 0x4E00..0x9FFF or
              cp in 0xA000..0xA4CF or
              cp in 0xAC00..0xD7A3 or
              cp in 0xF900..0xFAFF or
              cp in 0xFE30..0xFE4F or
              cp in 0xFF00..0xFF60 or
              cp in 0xFFE0..0xFFE6 or
              cp in 0x1F300..0x1F64F or
              cp in 0x1F900..0x1F9FF or
              cp in 0x20000..0x2FFFD or
              cp in 0x30000..0x3FFFD,
       do: 2

  defp char_width(_), do: 1
end

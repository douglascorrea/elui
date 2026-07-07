defmodule Elui.Text do
  @moduledoc """
  Multi-line styled text made of `Elui.Text.Line`s. Mirrors ratatui's
  `Text`.

  Most widgets accept anything that can be coerced into text: plain
  strings (split on newlines), spans, lines, or lists thereof.
  """

  alias Elui.Style
  alias Elui.Text.{Line, Span}

  defstruct lines: [], style: %Style{}, alignment: nil

  @type t :: %__MODULE__{
          lines: [Line.t()],
          style: Style.t(),
          alignment: :left | :center | :right | nil
        }

  @doc """
  Creates text from a string (split on `\\n`), a line, a span, or a
  list of lines/strings.

  Options: `:style` and `:alignment`.
  """
  @spec new(term(), Keyword.t()) :: t()
  def new(content, opts \\ []) do
    %__MODULE__{
      lines: coerce_lines(content),
      style: Style.to_style(Keyword.get(opts, :style)),
      alignment: Keyword.get(opts, :alignment)
    }
  end

  defp coerce_lines(%__MODULE__{lines: lines}), do: lines
  defp coerce_lines(%Line{} = line), do: [line]
  defp coerce_lines(%Span{} = span), do: [Line.to_line(span)]

  defp coerce_lines(content) when is_binary(content) do
    content
    |> String.split("\n")
    |> Enum.map(&Line.raw/1)
  end

  defp coerce_lines(list) when is_list(list) do
    Enum.flat_map(list, fn
      %Line{} = line -> [line]
      %Span{} = span -> [Line.to_line(span)]
      content when is_binary(content) -> coerce_lines(content)
    end)
  end

  @doc "Creates unstyled text."
  @spec raw(String.t()) :: t()
  def raw(content), do: new(content)

  @doc "Creates text where every line shares the given style."
  @spec styled(term(), Style.t() | Keyword.t()) :: t()
  def styled(content, style), do: new(content, style: Style.to_style(style))

  @doc "The display width of the widest line."
  @spec width(t()) :: non_neg_integer()
  def width(%__MODULE__{lines: lines}) do
    lines |> Enum.map(&Line.width/1) |> Enum.max(fn -> 0 end)
  end

  @doc "The number of lines."
  @spec height(t()) :: non_neg_integer()
  def height(%__MODULE__{lines: lines}), do: length(lines)

  @doc "Patches the text-level style."
  @spec patch_style(t(), Style.t() | Keyword.t()) :: t()
  def patch_style(%__MODULE__{} = text, style) do
    %{text | style: Style.patch(text.style, style)}
  end

  @doc "Sets the alignment for the whole text."
  @spec alignment(t(), :left | :center | :right) :: t()
  def alignment(%__MODULE__{} = text, alignment), do: %{text | alignment: alignment}

  @doc "Coerces any text-like value into `%Elui.Text{}`."
  @spec to_text(term()) :: t()
  def to_text(%__MODULE__{} = text), do: text
  def to_text(other), do: new(other)

  @doc """
  Replaces every character with the mask character, keeping the layout.
  Useful for password fields (ratatui's `Masked`).
  """
  @spec masked(String.t(), String.t()) :: t()
  def masked(content, mask \\ "*") do
    content
    |> String.split("\n")
    |> Enum.map(fn line -> String.duplicate(mask, String.length(line)) end)
    |> Enum.join("\n")
    |> new()
  end
end

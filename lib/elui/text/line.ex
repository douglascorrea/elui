defmodule Elui.Text.Line do
  @moduledoc """
  A single line of styled text made of `Elui.Text.Span`s, with an
  optional line-level style and alignment. Mirrors ratatui's `Line`.
  """

  alias Elui.Style
  alias Elui.Text.Span

  defstruct spans: [], style: %Style{}, alignment: nil

  @type t :: %__MODULE__{
          spans: [Span.t()],
          style: Style.t(),
          alignment: :left | :center | :right | nil
        }

  @doc """
  Creates a line from a string, a span, or a list of spans/strings.

  Options: `:style` and `:alignment`.
  """
  @spec new(String.t() | Span.t() | [Span.t() | String.t()], Keyword.t()) :: t()
  def new(content, opts \\ []) do
    spans =
      content
      |> List.wrap()
      |> Enum.map(&Span.to_span/1)

    %__MODULE__{
      spans: spans,
      style: Style.to_style(Keyword.get(opts, :style)),
      alignment: Keyword.get(opts, :alignment)
    }
  end

  @doc "Creates an unstyled line."
  @spec raw(String.t()) :: t()
  def raw(content), do: new(content)

  @doc "Creates a line where every span shares the given style."
  @spec styled(String.t() | [Span.t() | String.t()], Style.t() | Keyword.t()) :: t()
  def styled(content, style), do: new(content, style: Style.to_style(style))

  @doc "The display width of the line in terminal cells."
  @spec width(t()) :: non_neg_integer()
  def width(%__MODULE__{spans: spans}) do
    Enum.reduce(spans, 0, fn span, acc -> acc + Span.width(span) end)
  end

  @doc "Sets the alignment (`:left`, `:center` or `:right`)."
  @spec alignment(t(), :left | :center | :right) :: t()
  def alignment(%__MODULE__{} = line, alignment), do: %{line | alignment: alignment}

  @spec centered(t()) :: t()
  def centered(%__MODULE__{} = line), do: alignment(line, :center)

  @spec left_aligned(t()) :: t()
  def left_aligned(%__MODULE__{} = line), do: alignment(line, :left)

  @spec right_aligned(t()) :: t()
  def right_aligned(%__MODULE__{} = line), do: alignment(line, :right)

  @doc "Patches the line style (does not touch individual spans)."
  @spec patch_style(t(), Style.t() | Keyword.t()) :: t()
  def patch_style(%__MODULE__{} = line, style) do
    %{line | style: Style.patch(line.style, style)}
  end

  @doc "The plain, unstyled text content of the line."
  @spec to_text(t()) :: String.t()
  def to_text(%__MODULE__{spans: spans}) do
    Enum.map_join(spans, & &1.content)
  end

  @doc "Coerces strings, spans and lines into a line."
  @spec to_line(t() | Span.t() | String.t()) :: t()
  def to_line(%__MODULE__{} = line), do: line
  def to_line(%Span{} = span), do: new([span])
  def to_line(content) when is_binary(content), do: new(content)
end

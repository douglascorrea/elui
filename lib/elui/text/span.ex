defmodule Elui.Text.Span do
  @moduledoc """
  A string with a single style, the smallest unit of styled text.
  Mirrors ratatui's `Span`.
  """

  alias Elui.Style

  defstruct content: "", style: %Style{}

  @type t :: %__MODULE__{content: String.t(), style: Style.t()}

  @doc "Creates a span with an optional style (style struct or keyword list)."
  @spec new(String.t(), Style.t() | Keyword.t() | nil) :: t()
  def new(content, style \\ nil) do
    %__MODULE__{content: to_string(content), style: Style.to_style(style)}
  end

  @doc "Creates an unstyled span."
  @spec raw(String.t()) :: t()
  def raw(content), do: new(content)

  @doc "Creates a styled span."
  @spec styled(String.t(), Style.t() | Keyword.t()) :: t()
  def styled(content, style), do: new(content, style)

  @doc "The display width of the span in terminal cells."
  @spec width(t()) :: non_neg_integer()
  def width(%__MODULE__{content: content}), do: Elui.Text.Width.of(content)

  @doc "Patches the span's style with additional styling."
  @spec patch_style(t(), Style.t() | Keyword.t()) :: t()
  def patch_style(%__MODULE__{} = span, style) do
    %{span | style: Style.patch(span.style, style)}
  end

  @doc "Coerces strings and spans into spans."
  @spec to_span(t() | String.t()) :: t()
  def to_span(%__MODULE__{} = span), do: span
  def to_span(content) when is_binary(content), do: new(content)
end

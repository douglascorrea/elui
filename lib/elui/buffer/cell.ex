defmodule Elui.Buffer.Cell do
  @moduledoc """
  A single terminal cell: a grapheme (symbol) plus a style.
  Mirrors ratatui's `Cell`.
  """

  alias Elui.Style

  defstruct symbol: " ", style: %Style{}, skip: false

  @type t :: %__MODULE__{symbol: String.t(), style: Style.t(), skip: boolean()}

  @doc "An empty (space) cell."
  @spec empty() :: t()
  def empty, do: %__MODULE__{}

  @spec new(String.t(), Style.t() | Keyword.t() | nil) :: t()
  def new(symbol, style \\ nil) do
    %__MODULE__{symbol: symbol, style: Style.to_style(style)}
  end

  @doc "Sets the cell's symbol."
  @spec set_symbol(t(), String.t()) :: t()
  def set_symbol(%__MODULE__{} = cell, symbol), do: %{cell | symbol: symbol}

  @doc "Patches the cell's style."
  @spec set_style(t(), Style.t() | Keyword.t()) :: t()
  def set_style(%__MODULE__{} = cell, style) do
    %{cell | style: Style.patch(cell.style, style)}
  end

  @doc "Resets the cell to an empty space with default style."
  @spec reset(t()) :: t()
  def reset(_cell), do: empty()
end

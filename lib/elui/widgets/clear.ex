defmodule Elui.Widgets.Clear do
  @moduledoc """
  Resets every cell in an area, erasing anything rendered underneath.
  Render this before a popup to clear the background. Mirrors
  ratatui's `Clear`.
  """

  defstruct []

  @type t :: %__MODULE__{}

  @spec new() :: t()
  def new, do: %__MODULE__{}

  defimpl Elui.Widget do
    def render(_clear, area, buffer) do
      Elui.Buffer.clear(buffer, area)
    end
  end
end

defmodule Elui.Widgets.Modal do
  @moduledoc """
  Centered modal shell: clears a popup rect, then renders a content widget
  inside it. Apps own the content (for example a `TextArea` or `List`).
  """

  alias Elui.Frame
  alias Elui.Layout.Rect
  alias Elui.Widgets.Clear

  @doc """
  Renders `widget` in a centered popup over `frame`.

  Options:

    * `:horizontal` - width constraint (default `{:percentage, 70}`)
    * `:vertical` - height constraint (default `{:percentage, 50}`)
  """
  @spec render(Frame.t(), term(), Keyword.t()) :: Frame.t()
  def render(%Frame{} = frame, widget, opts \\ []) do
    area = area(frame, opts)

    frame
    |> Frame.render_widget(Clear.new(), area)
    |> Frame.render_widget(widget, area)
  end

  @doc """
  Like `render/3` for stateful widgets. Returns `{frame, state}`.
  """
  @spec render_stateful(Frame.t(), term(), term(), Keyword.t()) :: {Frame.t(), term()}
  def render_stateful(%Frame{} = frame, widget, state, opts \\ []) do
    area = area(frame, opts)
    frame = Frame.render_widget(frame, Clear.new(), area)
    Frame.render_stateful_widget(frame, widget, area, state)
  end

  @doc "Centered popup area for the current frame."
  @spec area(Frame.t(), Keyword.t()) :: Rect.t()
  def area(%Frame{} = frame, opts \\ []) do
    horizontal = Keyword.get(opts, :horizontal, {:percentage, 70})
    vertical = Keyword.get(opts, :vertical, {:percentage, 50})
    Rect.centered(Frame.area(frame), horizontal, vertical)
  end
end

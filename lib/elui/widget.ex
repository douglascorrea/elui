defprotocol Elui.Widget do
  @moduledoc """
  The rendering protocol implemented by every widget.

  A widget takes an area and a buffer and returns the updated buffer.
  Mirrors ratatui's `Widget` trait.
  """

  @doc "Renders the widget into `buffer` within `area`."
  @spec render(t(), Elui.Layout.Rect.t(), Elui.Buffer.t()) :: Elui.Buffer.t()
  def render(widget, area, buffer)
end

defprotocol Elui.StatefulWidget do
  @moduledoc """
  Rendering protocol for widgets that carry state between frames
  (list selection, table offsets, scrollbar position, ...).

  Mirrors ratatui's `StatefulWidget`: rendering returns both the
  updated buffer and the (possibly adjusted) state.
  """

  @doc "Renders the widget, returning `{buffer, state}`."
  @spec render(t(), Elui.Layout.Rect.t(), Elui.Buffer.t(), term()) :: {Elui.Buffer.t(), term()}
  def render(widget, area, buffer, state)
end

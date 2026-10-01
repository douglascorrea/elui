defmodule Elui.Frame do
  @moduledoc """
  A single frame of a draw call. The closure passed to
  `Elui.Terminal.draw/2` receives a frame, renders widgets into it and
  returns it. Mirrors ratatui's `Frame`.

  ## Example

      Terminal.draw(terminal, fn frame ->
        Frame.render_widget(frame, Paragraph.new("Hello"), Frame.area(frame))
      end)
  """

  alias Elui.Buffer
  alias Elui.Layout.Rect

  defstruct buffer: nil, area: %Rect{}, cursor_position: nil, count: 0, overlays: []

  @type overlay :: {integer(), integer(), iodata()}

  @type t :: %__MODULE__{
          buffer: Buffer.t(),
          area: Rect.t(),
          cursor_position: {integer(), integer()} | nil,
          count: non_neg_integer(),
          overlays: [overlay()]
        }

  @doc "The full area of the frame (the terminal size)."
  @spec area(t()) :: Rect.t()
  def area(%__MODULE__{area: area}), do: area

  @doc """
  Add a raw overlay payload to be written at `{x, y}` after the cell grid
  is flushed — the escape hatch for graphics protocols (sixel, kitty) and
  other out-of-grid bytes. The backend writes them in order; the cursor is
  positioned as usual afterwards. Overlays are not diffed: each frame gets
  exactly the overlays it declares.
  """
  @spec put_overlay(t(), integer(), integer(), iodata()) :: t()
  def put_overlay(%__MODULE__{} = frame, x, y, data) do
    %{frame | overlays: frame.overlays ++ [{x, y, data}]}
  end

  @doc "Renders a widget into the given area."
  @spec render_widget(t(), Elui.Widget.t(), Rect.t()) :: t()
  def render_widget(%__MODULE__{} = frame, widget, %Rect{} = area) do
    area = Rect.intersection(area, frame.area)
    %{frame | buffer: Elui.Widget.render(widget, area, frame.buffer)}
  end

  @doc """
  Renders a stateful widget into the given area, returning
  `{frame, new_state}`.
  """
  @spec render_stateful_widget(t(), Elui.StatefulWidget.t(), Rect.t(), term()) :: {t(), term()}
  def render_stateful_widget(%__MODULE__{} = frame, widget, %Rect{} = area, state) do
    area = Rect.intersection(area, frame.area)
    {buffer, state} = Elui.StatefulWidget.render(widget, area, frame.buffer, state)
    {%{frame | buffer: buffer}, state}
  end

  @doc """
  Sets the cursor position for this frame. The cursor is shown at the
  given position after the frame is flushed (useful for text inputs).
  """
  @spec set_cursor_position(t(), {integer(), integer()}) :: t()
  def set_cursor_position(%__MODULE__{} = frame, {_x, _y} = pos) do
    %{frame | cursor_position: pos}
  end
end

defmodule Elui.Terminal do
  @moduledoc """
  The main interface to draw UIs. Owns a backend, double-buffers
  frames and flushes only the diff between consecutive frames.
  Mirrors ratatui's `Terminal`.

  ## Example

      terminal = Terminal.new(backend: Elui.Backend.Ansi)

      {terminal, _frame} =
        Terminal.draw(terminal, fn frame ->
          Frame.render_widget(frame, Paragraph.new("Hello"), Frame.area(frame))
        end)

      Terminal.restore(terminal)
  """

  alias Elui.Backend
  alias Elui.Buffer
  alias Elui.Frame
  alias Elui.Layout.Rect

  defstruct backend: nil,
            backend_state: nil,
            previous_buffer: nil,
            area: %Rect{},
            hidden_cursor: false,
            frame_count: 0

  @type t :: %__MODULE__{}

  @doc """
  Creates a terminal.

  Options:

    * `:backend` - a module implementing `Elui.Backend`
      (default `Elui.Backend.Ansi`)
    * `:backend_opts` - options passed to the backend's `init/1`
  """
  @spec new(Keyword.t()) :: t()
  def new(opts \\ []) do
    backend = Keyword.get(opts, :backend, Elui.Backend.Ansi)
    backend_state = backend.init(Keyword.get(opts, :backend_opts, []))
    {width, height} = backend.size(backend_state)
    area = Rect.new(0, 0, width, height)

    %__MODULE__{
      backend: backend,
      backend_state: backend_state,
      previous_buffer: Buffer.empty(area),
      area: area
    }
  end

  @doc "The current terminal area."
  @spec area(t()) :: Rect.t()
  def area(%__MODULE__{area: area}), do: area

  @doc """
  Draws a frame. The function receives an `Elui.Frame`, renders
  widgets into it and returns either the frame or `{frame, result}`.

  Returns `{terminal, result}` where `result` is whatever the render
  function returned alongside the frame (or `nil`).
  """
  @spec draw(t(), (Frame.t() -> Frame.t() | {Frame.t(), term()})) :: {t(), term()}
  def draw(%__MODULE__{} = terminal, fun) when is_function(fun, 1) do
    terminal = autoresize(terminal)

    frame = %Frame{
      buffer: Buffer.empty(terminal.area),
      area: terminal.area,
      count: terminal.frame_count
    }

    {frame, result} =
      case fun.(frame) do
        %Frame{} = frame -> {frame, nil}
        {%Frame{} = frame, result} -> {frame, result}
      end

    updates = Buffer.diff(terminal.previous_buffer, frame.buffer)
    backend_state = terminal.backend.draw(terminal.backend_state, updates)

    backend_state =
      if function_exported?(terminal.backend, :draw_overlays, 2) do
        # Invoke even for [] so recording backends can clear prior-frame
        # overlays deterministically.
        terminal.backend.draw_overlays(backend_state, frame.overlays)
      else
        backend_state
      end

    {backend_state, hidden} =
      case frame.cursor_position do
        nil ->
          {terminal.backend.hide_cursor(backend_state), true}

        pos ->
          state = terminal.backend.set_cursor_position(backend_state, pos)
          {terminal.backend.show_cursor(state), false}
      end

    backend_state = terminal.backend.flush(backend_state)

    terminal = %{
      terminal
      | backend_state: backend_state,
        previous_buffer: frame.buffer,
        hidden_cursor: hidden,
        frame_count: terminal.frame_count + 1
    }

    {terminal, result}
  end

  @doc "Clears the terminal and forces a full redraw on the next frame."
  @spec clear(t()) :: t()
  def clear(%__MODULE__{} = terminal) do
    backend_state = terminal.backend.clear(terminal.backend_state)
    %{terminal | backend_state: backend_state, previous_buffer: Buffer.empty(terminal.area)}
  end

  @doc "Re-reads the terminal size, clearing when it changed."
  @spec autoresize(t()) :: t()
  def autoresize(%__MODULE__{} = terminal) do
    {width, height} = terminal.backend.size(terminal.backend_state)
    area = Rect.new(0, 0, width, height)

    if area == terminal.area do
      terminal
    else
      terminal = %{terminal | area: area, previous_buffer: Buffer.empty(area)}
      clear(terminal)
    end
  end

  @doc "Restores the terminal to its normal state. Call before exiting."
  @spec restore(t()) :: t()
  def restore(%__MODULE__{} = terminal) do
    %{terminal | backend_state: terminal.backend.restore(terminal.backend_state)}
  end

  @doc "The backend state (useful with `Elui.Backend.Test`)."
  @spec backend_state(t()) :: Backend.state()
  def backend_state(%__MODULE__{backend_state: state}), do: state
end

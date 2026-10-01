defmodule Elui.Backend.Test do
  @moduledoc """
  An in-memory backend for testing, equivalent to ratatui's
  `TestBackend`. Rendered output can be inspected with
  `buffer/1` or `to_lines/1`.
  """

  @behaviour Elui.Backend

  alias Elui.Buffer
  alias Elui.Layout.Rect

  defstruct width: 80, height: 24, buffer: nil, cursor_visible: true, cursor: {0, 0}, overlays: []

  @impl true
  def init(opts \\ []) do
    width = Keyword.get(opts, :width, 80)
    height = Keyword.get(opts, :height, 24)

    %__MODULE__{
      width: width,
      height: height,
      buffer: Buffer.empty(Rect.new(0, 0, width, height))
    }
  end

  @impl true
  def draw(state, updates) do
    buffer =
      Enum.reduce(updates, state.buffer, fn {x, y, cell}, buf ->
        Buffer.put(buf, x, y, cell)
      end)

    %{state | buffer: buffer}
  end

  @impl true
  def hide_cursor(state), do: %{state | cursor_visible: false}

  @impl true
  def show_cursor(state), do: %{state | cursor_visible: true}

  @impl true
  def set_cursor_position(state, pos), do: %{state | cursor: pos}

  @impl true
  def clear(state), do: %{state | buffer: Buffer.empty(state.buffer.area)}

  @impl true
  def size(state), do: {state.width, state.height}

  @impl true
  def flush(state), do: state

  @impl true
  def draw_overlays(state, overlays) do
    # Record this frame (don't render) — tests assert on the payloads.
    %{state | overlays: overlays}
  end

  @impl true
  def restore(state), do: state

  @doc "The current in-memory buffer."
  @spec buffer(%__MODULE__{}) :: Buffer.t()
  def buffer(%__MODULE__{buffer: buffer}), do: buffer

  @doc "The rendered content as a list of plain strings."
  @spec to_lines(%__MODULE__{}) :: [String.t()]
  def to_lines(%__MODULE__{buffer: buffer}), do: Buffer.to_lines(buffer)
end

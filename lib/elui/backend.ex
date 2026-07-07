defmodule Elui.Backend do
  @moduledoc """
  Behaviour implemented by terminal backends.

  A backend knows how to write cell updates to a real (or fake)
  terminal: moving the cursor, applying styles, clearing the screen.
  Mirrors ratatui's `Backend` trait.

  Built-in implementations:

    * `Elui.Backend.Ansi` - writes ANSI escape sequences to stdout
    * `Elui.Backend.Test` - renders into an in-memory buffer for tests
  """

  alias Elui.Buffer.Cell

  @type state :: term()

  @doc "Initializes the backend, returning its state."
  @callback init(Keyword.t()) :: state()

  @doc "Draws the given `{x, y, cell}` updates."
  @callback draw(state(), [{integer(), integer(), Cell.t()}]) :: state()

  @doc "Hides the cursor."
  @callback hide_cursor(state()) :: state()

  @doc "Shows the cursor."
  @callback show_cursor(state()) :: state()

  @doc "Moves the cursor to `{x, y}` (zero-based)."
  @callback set_cursor_position(state(), {integer(), integer()}) :: state()

  @doc "Clears the whole screen."
  @callback clear(state()) :: state()

  @doc "Returns the terminal size as `{width, height}`."
  @callback size(state()) :: {non_neg_integer(), non_neg_integer()}

  @doc "Flushes any buffered output."
  @callback flush(state()) :: state()

  @doc "Restores the terminal (leave alternate screen, show cursor...)."
  @callback restore(state()) :: state()
end

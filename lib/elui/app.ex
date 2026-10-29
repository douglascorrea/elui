defmodule Elui.App do
  @moduledoc """
  A small Elm-style application runner tying together the terminal,
  input events and a render loop. This plays the role of the
  hand-written event loops in ratatui applications.

  ## Usage

      defmodule Counter do
        @behaviour Elui.App

        @impl true
        def init(_opts), do: 0

        @impl true
        def update(count, {:key, {:char, "q"}, _mods}), do: :quit
        def update(count, {:key, :up, _mods}), do: {:ok, count + 1}
        def update(count, {:key, :down, _mods}), do: {:ok, count - 1}
        def update(count, _event), do: {:ok, count}

        @impl true
        def view(count, frame) do
          Elui.Frame.render_widget(
            frame,
            Elui.Widgets.Paragraph.new("Count: \#{count} (q quits)"),
            Elui.Frame.area(frame)
          )
        end
      end

      Elui.App.run(Counter)

  ## Events passed to `c:update/2`

    * `{:key, key, modifiers}` - see `Elui.Input`
    * `:tick` - emitted every `:tick_rate` milliseconds
    * `{:resize, width, height}` - terminal size at startup or after a resize
    * `{:mouse, kind, x, y, modifiers}` - mouse input when `:mouse` is enabled
    * `{:message, message}` - any non-input message sent to the app process
  """

  alias Elui.Frame
  alias Elui.Input
  alias Elui.Terminal

  # Most events applied between two frames.
  @max_batch 64

  @type model :: term()
  @type event ::
          {:key, term(), [atom()]}
          | {:mouse, term(), non_neg_integer(), non_neg_integer(), [atom()]}
          | :tick
          | {:resize, non_neg_integer(), non_neg_integer()}
          | {:message, term()}

  @doc "Builds the initial model."
  @callback init(Keyword.t()) :: model()

  @doc """
  Handles an event. Return `{:ok, model}` to continue, or `:quit` /
  `{:quit, model}` to stop the application.
  """
  @callback update(model(), event()) :: {:ok, model()} | :quit | {:quit, model()}

  @doc "Renders the model into the frame."
  @callback view(model(), Frame.t()) :: Frame.t()

  @doc """
  Runs the application until `c:update/2` returns `:quit`.

  Options:

    * `:tick_rate` - milliseconds between `:tick` events (default 250)
    * `:terminal` - options forwarded to `Elui.Terminal.new/1`
    * `:mouse` - enables SGR mouse capture while the app runs (default `false`)
    * `:input` - reads keys and mouse from the terminal (default `true`).
      With `false` the app gets only the messages sent to its process,
      `{:elui_event, event}` among them, as in a test or a host that reads
      input itself

  Events that arrive while a frame is drawn are applied together before the
  next frame, in the order they arrived and up to 64 at a time, so an app
  keeps up with fast typing even when a frame takes longer than a keystroke.
  An update that quits stops the batch, and later events are left unread.

  Returns the final model.
  """
  @spec run(module(), Keyword.t()) :: model()
  def run(module, opts \\ []) do
    tick_rate = Keyword.get(opts, :tick_rate, 250)
    mouse? = Keyword.get(opts, :mouse, false)
    terminal = Terminal.new(Keyword.get(opts, :terminal, []))
    input = if Keyword.get(opts, :input, true), do: Input.start(self(), mouse: mouse?)

    model = module.init(opts)
    area = Terminal.area(terminal)

    try do
      case module.update(model, {:resize, area.width, area.height}) do
        {:ok, model} -> loop(module, model, terminal, tick_rate)
        :quit -> model
        {:quit, model} -> model
      end
    after
      Terminal.restore(terminal)
      if input, do: Input.stop(input)
    end
  end

  defp loop(module, model, terminal, tick_rate) do
    size_before = Terminal.area(terminal)
    {terminal, _} = Terminal.draw(terminal, fn frame -> module.view(model, frame) end)

    event =
      case next_event(tick_rate) do
        {:ok, event} -> event
        :timeout -> :tick
      end

    # Detect resizes between frames so apps can react to them.
    events =
      case Terminal.area(Terminal.autoresize(terminal)) do
        ^size_before -> [event]
        area -> [{:resize, area.width, area.height}, event]
      end

    with {:continue, model} <- apply_events(module, model, events),
         {:continue, model} <- apply_queued(module, model, @max_batch - 1) do
      loop(module, model, terminal, tick_rate)
    else
      {:quit, final} -> final
    end
  end

  # Applies the events already waiting, in arrival order and without waiting
  # for more, so a burst of input costs one frame rather than one frame per
  # event. At most `budget` of them, so a flood can't hold off drawing.
  defp apply_queued(_module, model, 0), do: {:continue, model}

  defp apply_queued(module, model, budget) do
    case next_event(0) do
      {:ok, event} ->
        with {:continue, model} <- apply_events(module, model, [event]) do
          apply_queued(module, model, budget - 1)
        end

      :timeout ->
        {:continue, model}
    end
  end

  defp next_event(timeout) do
    receive do
      {:elui_event, event} -> {:ok, event}
      message -> {:ok, {:message, message}}
    after
      timeout -> :timeout
    end
  end

  defp apply_events(_module, model, []), do: {:continue, model}

  defp apply_events(module, model, [event | rest]) do
    case module.update(model, event) do
      {:ok, new_model} -> apply_events(module, new_model, rest)
      :quit -> {:quit, model}
      {:quit, new_model} -> {:quit, new_model}
    end
  end
end

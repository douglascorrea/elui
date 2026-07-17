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

  Returns the final model.
  """
  @spec run(module(), Keyword.t()) :: model()
  def run(module, opts \\ []) do
    tick_rate = Keyword.get(opts, :tick_rate, 250)
    mouse? = Keyword.get(opts, :mouse, false)
    terminal = Terminal.new(Keyword.get(opts, :terminal, []))
    input = Input.start(self(), mouse: mouse?)

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
      Input.stop(input)
    end
  end

  defp loop(module, model, terminal, tick_rate) do
    size_before = Terminal.area(terminal)
    {terminal, _} = Terminal.draw(terminal, fn frame -> module.view(model, frame) end)

    event =
      receive do
        {:elui_event, event} -> event
        message -> {:message, message}
      after
        tick_rate -> :tick
      end

    # Detect resizes between frames so apps can react to them.
    events =
      case Terminal.area(Terminal.autoresize(terminal)) do
        ^size_before -> [event]
        area -> [{:resize, area.width, area.height}, event]
      end

    case apply_events(module, model, events) do
      {:quit, final} -> final
      {:continue, model} -> loop(module, model, terminal, tick_rate)
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

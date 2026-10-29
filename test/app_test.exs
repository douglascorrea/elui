defmodule Elui.AppTest do
  use ExUnit.Case, async: true

  # Records every event it is given and reports each frame it draws to the
  # test. Events in `:queue` are already waiting when the loop starts.
  defmodule Recorder do
    @behaviour Elui.App

    @impl true
    def init(opts) do
      Enum.each(Keyword.get(opts, :queue, []), &send(self(), &1))
      %{test: Keyword.fetch!(opts, :test), events: []}
    end

    @impl true
    def update(_model, {:key, {:char, "q"}, _mods}), do: :quit
    def update(model, {:message, :stop}), do: {:quit, model}
    def update(model, event), do: {:ok, %{model | events: model.events ++ [event]}}

    @impl true
    def view(model, frame) do
      send(model.test, {:frame, model.events})
      frame
    end
  end

  defp start(opts) do
    test = self()

    defaults = [
      test: test,
      input: false,
      tick_rate: 60_000,
      terminal: [backend: Elui.Backend.Test, backend_opts: [width: 10, height: 2]]
    ]

    Task.async(fn -> Elui.App.run(Recorder, Keyword.merge(defaults, opts)) end)
  end

  defp key(char), do: {:elui_event, {:key, {:char, char}, []}}

  test "events waiting together are applied in arrival order and drawn once" do
    app = start(queue: [key("a"), :hello, key("b"), key("c")])
    resize = {:resize, 10, 2}

    assert_receive {:frame, [^resize]}

    assert_receive {:frame,
                    [
                      ^resize,
                      {:key, {:char, "a"}, []},
                      {:message, :hello},
                      {:key, {:char, "b"}, []},
                      {:key, {:char, "c"}, []}
                    ]}

    send(app.pid, :stop)
    final = Task.await(app)

    assert length(final.events) == 5
    refute_received {:frame, _}
  end

  test "an event that quits ends the batch and later events are not applied" do
    app = start(queue: [key("a"), key("q"), key("b")])

    final = Task.await(app)

    assert final.events == [{:resize, 10, 2}, {:key, {:char, "a"}, []}]
    assert_received {:frame, [{:resize, 10, 2}]}
    refute_received {:frame, _}
  end

  test "a flood of events is applied in batches of at most 64" do
    app = start(queue: Enum.map(1..70, fn _ -> key("x") end))

    assert_receive {:frame, events} when length(events) == 1
    assert_receive {:frame, events} when length(events) == 65
    assert_receive {:frame, events} when length(events) == 71

    send(app.pid, :stop)
    Task.await(app)
    refute_received {:frame, _}
  end

  test "ticks come when nothing arrives within the tick rate" do
    app = start(tick_rate: 10)

    assert_receive {:frame, [{:resize, 10, 2}, :tick]}
    send(app.pid, :stop)
    Task.await(app)
  end
end

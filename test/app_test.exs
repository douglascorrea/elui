defmodule Elui.AppTest do
  use ExUnit.Case, async: true

  defmodule Counter do
    @behaviour Elui.App

    @impl true
    def init(_opts), do: 0

    @impl true
    def update(count, {:key, {:char, "+"}, _mods}), do: {:ok, count + 1}
    def update(count, {:key, {:char, "q"}, _mods}), do: {:quit, count}
    def update(count, _event), do: {:ok, count}

    @impl true
    def view(count, frame) do
      Elui.Frame.render_widget(
        frame,
        Elui.Widgets.Paragraph.new("count: #{count}"),
        Elui.Frame.area(frame)
      )
    end
  end

  describe "run/2 with input: false" do
    test "runs the full loop driven by sent events, without touching a terminal" do
      task =
        Task.async(fn ->
          Elui.App.run(Counter,
            input: false,
            tick_rate: :infinity,
            terminal: [backend: Elui.Backend.Test, backend_opts: [width: 12, height: 1]]
          )
        end)

      send(task.pid, {:elui_event, {:key, {:char, "+"}, []}})
      send(task.pid, {:elui_event, {:key, {:char, "+"}, []}})
      send(task.pid, {:elui_event, {:key, {:char, "q"}, []}})

      assert Task.await(task) == 2
    end

    test "an init crash still restores the terminal" do
      defmodule CrashOnInit do
        @behaviour Elui.App

        @impl true
        def init(_opts), do: raise("boom")

        @impl true
        def update(model, _event), do: {:ok, model}

        @impl true
        def view(_model, frame), do: frame
      end

      # The try/after must already be in force when init runs. Before this test,
      # a crash in init skipped Terminal.restore entirely and left a real
      # terminal in the alternate screen with the cursor hidden.
      assert_raise RuntimeError, "boom", fn ->
        Elui.App.run(CrashOnInit,
          input: false,
          terminal: [backend: Elui.Backend.Test]
        )
      end
    end
  end
end

defmodule ExamplesCompileTest do
  use ExUnit.Case, async: false

  @ratatui_apps ~w(
    advanced-widget-impl
    async-github
    calendar-explorer
    canvas
    chart
    color-explorer
    colors-rgb
    constraint-explorer
    constraints
    custom-widget
    demo
    demo2
    flex
    gauge
    hello-world
    hyperlink
    inline
    input-form
    minimal
    modifiers
    mouse-drawing
    panic
    popup
    release-header
    scrollbar
    table
    todo-list
    tracing
    user-input
    volatility-surface
    weather
    widget-ref-container
  )

  test "every Ratatui app has a loadable Elui example" do
    previous = System.get_env("ELUI_SKIP_EXAMPLE_RUN")
    System.put_env("ELUI_SKIP_EXAMPLE_RUN", "1")

    try do
      for app <- @ratatui_apps do
        file = Path.expand("examples/#{String.replace(app, "-", "_")}.exs")
        assert File.exists?(file), "missing example for #{app}: #{file}"
        assert [{_module, _bytecode} | _] = Code.require_file(file)
      end
    after
      if previous do
        System.put_env("ELUI_SKIP_EXAMPLE_RUN", previous)
      else
        System.delete_env("ELUI_SKIP_EXAMPLE_RUN")
      end
    end
  end
end

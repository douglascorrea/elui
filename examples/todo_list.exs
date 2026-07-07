Code.require_file("support/ratatui_port.exs", __DIR__)

# Todo list demo: add, toggle, select and delete tasks.
#
# Run with:
#
#     mix run examples/todo_list.exs

defmodule Examples.TodoList do
  @behaviour Elui.App

  alias Elui.{Frame, Layout}
  alias Elui.Text.{Line, Span}
  alias Elui.Widgets.{Block, Paragraph}
  alias Elui.Widgets.List, as: UiList

  @impl true
  def init(_opts) do
    %{
      todos: [
        %{text: "Port Ratatui apps", done: false},
        %{text: "Run the Elui test suite", done: true},
        %{text: "Commit the examples", done: false}
      ],
      selected: 0,
      mode: :browse,
      input: ""
    }
  end

  @impl true
  def update(model, event) do
    case model.mode do
      :browse -> update_browse(model, event)
      :add -> update_add(model, event)
    end
  end

  defp update_browse(model, event) do
    cond do
      Examples.Support.quit?(event) ->
        :quit

      Examples.Support.key?(event, [:down, {:char, "j"}]) ->
        {:ok, %{model | selected: Examples.Support.cycle(model.selected, 1, length(model.todos))}}

      Examples.Support.key?(event, [:up, {:char, "k"}]) ->
        {:ok, %{model | selected: Examples.Support.cycle(model.selected, -1, length(model.todos))}}

      Examples.Support.key?(event, [:space, :enter]) ->
        {:ok, toggle(model)}

      Examples.Support.key?(event, {:char, "a"}) ->
        {:ok, %{model | mode: :add, input: ""}}

      Examples.Support.key?(event, {:char, "d"}) ->
        {:ok, delete_selected(model)}

      true ->
        {:ok, model}
    end
  end

  defp update_add(model, event) do
    cond do
      Examples.Support.key?(event, :esc) ->
        {:ok, %{model | mode: :browse, input: ""}}

      Examples.Support.key?(event, :enter) ->
        add_todo(model)

      Examples.Support.key?(event, :backspace) ->
        {:ok, %{model | input: String.slice(model.input, 0, max(String.length(model.input) - 1, 0))}}

      match?({:key, {:char, _}, []}, event) ->
        {:key, {:char, char}, []} = event
        {:ok, %{model | input: model.input <> char}}

      Examples.Support.key?(event, :space) ->
        {:ok, %{model | input: model.input <> " "}}

      true ->
        {:ok, model}
    end
  end

  @impl true
  def view(model, frame) do
    [header, body, input, footer] =
      Layout.vertical([{:length, 2}, {:fill, 1}, {:length, 3}, {:length, 1}])
      |> Layout.split(Frame.area(frame))

    frame =
      Examples.Support.render_header(
        frame,
        header,
        "Todo List",
        "a add, Space toggle, d delete"
      )

    items =
      Enum.map(model.todos, fn todo ->
        marker = if todo.done, do: "[x] ", else: "[ ] "

        Line.new([
          Span.new(marker, fg: if(todo.done, do: :green, else: :dark_gray)),
          Span.new(todo.text, add_modifier: if(todo.done, do: [:crossed_out], else: []))
        ])
      end)

    {frame, _} =
      Frame.render_stateful_widget(
        frame,
        UiList.new(items,
          block: Block.bordered(title: "Tasks"),
          highlight_style: [bg: :blue],
          highlight_symbol: "> "
        ),
        body,
        UiList.State.new(selected: model.selected)
      )

    frame =
      Frame.render_widget(
        frame,
        Paragraph.new(model.input,
          block:
            Block.bordered(
              title: if(model.mode == :add, do: "New task", else: "Press a to add"),
              border_style: [fg: if(model.mode == :add, do: :yellow, else: :dark_gray)]
            )
        ),
        input
      )

    frame =
      if model.mode == :add do
        Frame.set_cursor_position(frame, {input.x + 1 + String.length(model.input), input.y + 1})
      else
        frame
      end

    Examples.Support.render_footer(frame, footer, "q/Esc quit")
  end

  defp toggle(model) do
    todos = List.update_at(model.todos, model.selected, &%{&1 | done: !&1.done})
    %{model | todos: todos}
  end

  defp delete_selected(%{todos: []} = model), do: model

  defp delete_selected(model) do
    todos = List.delete_at(model.todos, model.selected)
    %{model | todos: todos, selected: min(model.selected, max(length(todos) - 1, 0))}
  end

  defp add_todo(%{input: ""} = model), do: {:ok, %{model | mode: :browse}}

  defp add_todo(model) do
    todo = %{text: model.input, done: false}
    todos = model.todos ++ [todo]
    {:ok, %{model | todos: todos, selected: length(todos) - 1, mode: :browse, input: ""}}
  end
end

Examples.Support.run(Examples.TodoList)

# User input example: a text field with cursor handling and a message
# history, in the spirit of ratatui's user-input example.
#
# Run with:
#
#     mix run examples/user_input.exs
#
# Type to edit, Enter submits, Esc quits.

defmodule Examples.UserInput do
  @behaviour Elui.App

  alias Elui.{Frame, Layout}
  alias Elui.Widgets.{Block, Paragraph}
  alias Elui.Widgets.List, as: UiList

  @impl true
  def init(_opts), do: %{input: "", cursor: 0, messages: []}

  @impl true
  def update(_model, {:key, :esc, _mods}), do: :quit

  def update(model, {:key, :enter, _mods}) do
    if model.input == "" do
      {:ok, model}
    else
      {:ok, %{model | messages: model.messages ++ [model.input], input: "", cursor: 0}}
    end
  end

  def update(model, {:key, :backspace, _mods}) when model.cursor > 0 do
    {before, rest} = String.split_at(model.input, model.cursor)
    {:ok, %{model | input: String.slice(before, 0..-2//1) <> rest, cursor: model.cursor - 1}}
  end

  def update(model, {:key, :left, _mods}) do
    {:ok, %{model | cursor: max(model.cursor - 1, 0)}}
  end

  def update(model, {:key, :right, _mods}) do
    {:ok, %{model | cursor: min(model.cursor + 1, String.length(model.input))}}
  end

  def update(model, {:key, {:char, ch}, []}) do
    {before, rest} = String.split_at(model.input, model.cursor)
    {:ok, %{model | input: before <> ch <> rest, cursor: model.cursor + 1}}
  end

  def update(model, {:key, :space, []}) do
    update(model, {:key, {:char, " "}, []})
  end

  def update(model, _event), do: {:ok, model}

  @impl true
  def view(model, frame) do
    [help_area, input_area, messages_area] =
      Layout.vertical([{:length, 1}, {:length, 3}, {:fill, 1}])
      |> Layout.split(Frame.area(frame))

    frame =
      Frame.render_widget(
        frame,
        Paragraph.new("Type a message. Enter submits, Esc quits.", style: [fg: :dark_gray]),
        help_area
      )

    frame =
      Frame.render_widget(
        frame,
        Paragraph.new(model.input, block: Block.bordered(title: "Input", border_style: [fg: :yellow])),
        input_area
      )

    # Place the terminal cursor inside the input box.
    frame = Frame.set_cursor_position(frame, {input_area.x + 1 + model.cursor, input_area.y + 1})

    messages =
      model.messages
      |> Enum.with_index()
      |> Enum.map(fn {msg, i} -> "#{i}: #{msg}" end)

    {frame, _} =
      Frame.render_stateful_widget(
        frame,
        UiList.new(messages, block: Block.bordered(title: "Messages")),
        messages_area,
        UiList.State.new()
      )

    frame
  end
end

Elui.App.run(Examples.UserInput)

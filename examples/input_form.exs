Code.require_file("support/ratatui_port.exs", __DIR__)

# Input Form demo: handles focus and editing across multiple fields.
#
# Run with:
#
#     mix run examples/input_form.exs

defmodule Examples.InputForm do
  @behaviour Elui.App

  alias Elui.{Frame, Layout}
  alias Elui.Widgets.{Block, Paragraph}

  @fields [:name, :email, :age]

  @impl true
  def init(_opts), do: %{focus: 0, values: %{name: "", email: "", age: ""}, submitted: nil}

  @impl true
  def update(model, event) do
    cond do
      Examples.Support.quit?(event) ->
        :quit

      Examples.Support.key?(event, [:tab, :down]) ->
        {:ok, %{model | focus: Examples.Support.cycle(model.focus, 1, length(@fields))}}

      Examples.Support.key?(event, [:back_tab, :up]) ->
        {:ok, %{model | focus: Examples.Support.cycle(model.focus, -1, length(@fields))}}

      Examples.Support.key?(event, :enter) ->
        {:ok, %{model | submitted: model.values}}

      Examples.Support.key?(event, :backspace) ->
        {:ok, update_field(model, &String.slice(&1, 0, max(String.length(&1) - 1, 0)))}

      match?({:key, {:char, _}, []}, event) ->
        {:key, {:char, char}, []} = event
        maybe_insert(model, char)

      Examples.Support.key?(event, :space) ->
        maybe_insert(model, " ")

      true ->
        {:ok, model}
    end
  end

  @impl true
  def view(model, frame) do
    [header, body, footer] =
      Layout.vertical([{:length, 2}, {:fill, 1}, {:length, 1}])
      |> Layout.split(Frame.area(frame))

    [form, summary] =
      Layout.horizontal([{:percentage, 55}, {:fill, 1}], spacing: 1)
      |> Layout.split(body)

    frame =
      Examples.Support.render_header(
        frame,
        header,
        "Input Form",
        "Tab focus, Enter submit, q quit"
      )

    frame =
      form_rows(form)
      |> Enum.with_index()
      |> Enum.reduce(frame, fn {{field, area}, i}, acc ->
        value = Map.fetch!(model.values, field)
        title = "#{label(field)}#{if i == model.focus, do: " *", else: ""}"

        Frame.render_widget(
          acc,
          Paragraph.new(value,
            block:
              Block.bordered(
                title: title,
                border_style: [fg: if(i == model.focus, do: :yellow, else: :dark_gray)]
              )
          ),
          area
        )
      end)

    {active_field, active_area} = Enum.at(form_rows(form), model.focus)
    cursor_x = active_area.x + 1 + String.length(Map.fetch!(model.values, active_field))
    frame = Frame.set_cursor_position(frame, {cursor_x, active_area.y + 1})

    submitted =
      case model.submitted do
        nil -> "Nothing submitted yet."
        values -> "Name: #{values.name}\nEmail: #{values.email}\nAge: #{values.age}"
      end

    frame =
      Frame.render_widget(
        frame,
        Paragraph.new(submitted, block: Block.bordered(title: "Submitted"), wrap: [trim: true]),
        summary
      )

    Examples.Support.render_footer(frame, footer, "The age field accepts digits only.")
  end

  defp maybe_insert(model, char) do
    field = Enum.at(@fields, model.focus)

    if field == :age and not String.match?(char, ~r/^\d$/) do
      {:ok, model}
    else
      {:ok, update_field(model, &(&1 <> char))}
    end
  end

  defp update_field(model, fun) do
    field = Enum.at(@fields, model.focus)
    %{model | values: Map.update!(model.values, field, fun)}
  end

  defp form_rows(area) do
    Layout.vertical([{:length, 3}, {:length, 3}, {:length, 3}], spacing: 1)
    |> Layout.split(area)
    |> Enum.zip(@fields)
    |> Enum.map(fn {area, field} -> {field, area} end)
  end

  defp label(:name), do: "Name"
  defp label(:email), do: "Email"
  defp label(:age), do: "Age"
end

Examples.Support.run(Examples.InputForm)

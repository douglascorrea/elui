Code.require_file("support/ratatui_port.exs", __DIR__)

# Constraint explorer demo: interactively adjust a set of layout
# constraints and see the resulting rectangles.
#
# Run with:
#
#     mix run examples/constraint_explorer.exs

defmodule Examples.ConstraintExplorer do
  @behaviour Elui.App

  alias Elui.{Frame, Layout}
  alias Elui.Widgets.{Block, Paragraph}

  @kinds [:length, :percentage, :ratio, :fill, :min, :max]

  @impl true
  def init(_opts) do
    %{
      selected: 0,
      direction: :horizontal,
      constraints: [
        {:length, 16},
        {:percentage, 30},
        {:fill, 1},
        {:min, 12}
      ]
    }
  end

  @impl true
  def update(model, event) do
    cond do
      Examples.Support.quit?(event) ->
        :quit

      Examples.Support.key?(event, [:up, {:char, "k"}]) ->
        {:ok, %{model | selected: Examples.Support.cycle(model.selected, -1, length(model.constraints))}}

      Examples.Support.key?(event, [:down, {:char, "j"}]) ->
        {:ok, %{model | selected: Examples.Support.cycle(model.selected, 1, length(model.constraints))}}

      Examples.Support.key?(event, [:left, {:char, "h"}]) ->
        {:ok, update_selected(model, -1)}

      Examples.Support.key?(event, [:right, {:char, "l"}]) ->
        {:ok, update_selected(model, 1)}

      Examples.Support.key?(event, [:tab, {:char, "t"}]) ->
        {:ok, cycle_kind(model)}

      Examples.Support.key?(event, {:char, "d"}) ->
        {:ok, %{model | direction: if(model.direction == :horizontal, do: :vertical, else: :horizontal)}}

      true ->
        {:ok, model}
    end
  end

  @impl true
  def view(model, frame) do
    [header, body, footer] =
      Layout.vertical([{:length, 2}, {:fill, 1}, {:length, 2}])
      |> Layout.split(Frame.area(frame))

    [controls, preview] =
      Layout.horizontal([{:length, 32}, {:fill, 1}], spacing: 1)
      |> Layout.split(body)

    frame =
      Examples.Support.render_header(
        frame,
        header,
        "Constraint Explorer",
        "j/k choose, h/l adjust, t type, d direction"
      )

    controls_text =
      model.constraints
      |> Enum.with_index()
      |> Enum.map(fn {constraint, i} ->
        prefix = if i == model.selected, do: "> ", else: "  "
        "#{prefix}#{label(constraint)}"
      end)
      |> Enum.join("\n")

    frame =
      Examples.Support.render_panel(
        frame,
        controls,
        "Constraints",
        controls_text <> "\n\nDirection: #{model.direction}",
        wrap: false
      )

    frame = render_preview(frame, preview, model)
    Examples.Support.render_footer(frame, footer, "Layout.split/2 recalculates the rectangles each frame.")
  end

  defp render_preview(frame, area, model) do
    layout =
      Layout.new(
        direction: model.direction,
        constraints: model.constraints,
        spacing: 1
      )

    layout
    |> Layout.split(area)
    |> Enum.with_index()
    |> Enum.reduce(frame, fn {rect, i}, acc ->
      Frame.render_widget(
        acc,
        Paragraph.new("#{rect.width}x#{rect.height}",
          alignment: :center,
          block:
            Block.bordered(
              title: label(Enum.at(model.constraints, i)),
              border_style: [fg: if(i == model.selected, do: :yellow, else: :dark_gray)]
            )
        ),
        rect
      )
    end)
  end

  defp update_selected(model, delta) do
    constraints = List.update_at(model.constraints, model.selected, &bump(&1, delta))
    %{model | constraints: constraints}
  end

  defp cycle_kind(model) do
    constraints =
      List.update_at(model.constraints, model.selected, fn constraint ->
        current = elem(constraint, 0)
        kind = Enum.at(@kinds, Examples.Support.cycle(Enum.find_index(@kinds, &(&1 == current)), 1, length(@kinds)))
        default_constraint(kind)
      end)

    %{model | constraints: constraints}
  end

  defp bump({:length, n}, delta), do: {:length, max(n + delta, 1)}
  defp bump({:percentage, n}, delta), do: {:percentage, Examples.Support.clamp(n + delta * 5, 0, 100)}
  defp bump({:ratio, n, d}, delta), do: {:ratio, max(n + delta, 1), d}
  defp bump({:fill, n}, delta), do: {:fill, max(n + delta, 1)}
  defp bump({:min, n}, delta), do: {:min, max(n + delta, 0)}
  defp bump({:max, n}, delta), do: {:max, max(n + delta, 0)}

  defp default_constraint(:length), do: {:length, 12}
  defp default_constraint(:percentage), do: {:percentage, 25}
  defp default_constraint(:ratio), do: {:ratio, 1, 3}
  defp default_constraint(:fill), do: {:fill, 1}
  defp default_constraint(:min), do: {:min, 10}
  defp default_constraint(:max), do: {:max, 20}

  defp label({:ratio, n, d}), do: "ratio #{n}/#{d}"
  defp label({kind, value}), do: "#{kind} #{value}"
end

Examples.Support.run(Examples.ConstraintExplorer)

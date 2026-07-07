defmodule Elui.Widgets.Chart.Axis do
  @moduledoc "An X or Y axis for `Elui.Widgets.Chart`."

  alias Elui.Style
  alias Elui.Text.Line

  defstruct title: nil, bounds: {0.0, 1.0}, labels: [], style: %Style{}, labels_alignment: :left

  @type t :: %__MODULE__{}

  @spec new(Keyword.t()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      title: opts[:title] && Line.to_line(opts[:title]),
      bounds: Keyword.get(opts, :bounds, {0.0, 1.0}),
      labels: opts |> Keyword.get(:labels, []) |> Enum.map(&Line.to_line/1),
      style: Style.to_style(Keyword.get(opts, :style)),
      labels_alignment: Keyword.get(opts, :labels_alignment, :left)
    }
  end
end

defmodule Elui.Widgets.Chart.Dataset do
  @moduledoc "A named data series for `Elui.Widgets.Chart`."

  alias Elui.Style

  defstruct name: nil, data: [], marker: :braille, graph_type: :scatter, style: %Style{}

  @type t :: %__MODULE__{}

  @doc """
  Creates a dataset from `{x, y}` points.

  Options: `:name`, `:marker`, `:graph_type` (`:scatter`, `:line` or
  `:bar`), `:style`.
  """
  @spec new([{number(), number()}], Keyword.t()) :: t()
  def new(data, opts \\ []) do
    %__MODULE__{
      name: Keyword.get(opts, :name),
      data: data,
      marker: Keyword.get(opts, :marker, :braille),
      graph_type: Keyword.get(opts, :graph_type, :scatter),
      style: Style.to_style(Keyword.get(opts, :style))
    }
  end
end

defmodule Elui.Widgets.Chart do
  @moduledoc """
  An X-Y chart with axes, labels, legend and multiple datasets drawn
  as scatter points, lines or bars. Mirrors ratatui's `Chart`.

  ## Example

      Chart.new(
        [
          Dataset.new([{0.0, 0.0}, {1.0, 2.0}, {2.0, 1.0}],
            name: "data1",
            graph_type: :line,
            style: [fg: :cyan]
          )
        ],
        x_axis: Axis.new(title: "X", bounds: {0.0, 2.0}, labels: ["0", "1", "2"]),
        y_axis: Axis.new(title: "Y", bounds: {0.0, 2.0}, labels: ["0", "1", "2"]),
        block: Block.bordered(title: "Chart")
      )
  """

  alias Elui.Buffer
  alias Elui.Layout.Rect
  alias Elui.Style
  alias Elui.Text.Line
  alias Elui.Widgets.Block
  alias Elui.Widgets.Canvas
  alias Elui.Widgets.Canvas.Context
  alias Elui.Widgets.Canvas.Shapes
  alias Elui.Widgets.Chart.{Axis, Dataset}

  defstruct datasets: [],
            x_axis: %Axis{},
            y_axis: %Axis{},
            block: nil,
            style: %Style{},
            hidden_legend: false

  @type t :: %__MODULE__{}

  @doc """
  Creates a chart from datasets.

  Options: `:x_axis`, `:y_axis` (`Elui.Widgets.Chart.Axis`), `:block`,
  `:style`, `:hidden_legend`.
  """
  @spec new([Dataset.t()], Keyword.t()) :: t()
  def new(datasets, opts \\ []) do
    %__MODULE__{
      datasets: datasets,
      x_axis: Keyword.get(opts, :x_axis, Axis.new()),
      y_axis: Keyword.get(opts, :y_axis, Axis.new()),
      block: Keyword.get(opts, :block),
      style: Style.to_style(Keyword.get(opts, :style)),
      hidden_legend: Keyword.get(opts, :hidden_legend, false)
    }
  end

  @doc false
  def render_into(%__MODULE__{} = chart, area, buffer) do
    buffer = Buffer.set_style(buffer, area, chart.style)
    {inner, buffer} = Block.render_with_block(chart.block, area, buffer)

    if Rect.empty?(inner) do
      buffer
    else
      y_label_width =
        chart.y_axis.labels
        |> Enum.map(&Line.width/1)
        |> Enum.max(fn -> 0 end)

      x_labels_height = if chart.x_axis.labels == [], do: 0, else: 1

      graph =
        Rect.inner(inner,
          left: if(y_label_width > 0, do: y_label_width + 1, else: 0),
          right: 0,
          top: 0,
          bottom:
            x_labels_height +
              if(chart.x_axis.labels != [] or chart.y_axis.labels != [], do: 1, else: 0)
        )

      if Rect.empty?(graph) do
        buffer
      else
        buffer
        |> draw_axes(chart, inner, graph)
        |> draw_labels(chart, inner, graph, y_label_width)
        |> draw_datasets(chart, graph)
        |> draw_legend(chart, graph)
        |> draw_titles(chart, inner, graph)
      end
    end
  end

  defp draw_axes(buffer, chart, _inner, graph) do
    axis_y = Rect.bottom(graph)
    axis_x = graph.x - 1

    buffer =
      if axis_x >= 0 do
        Enum.reduce(graph.y..(Rect.bottom(graph) - 1)//1, buffer, fn y, buf ->
          Buffer.put(buf, axis_x, y, Elui.Buffer.Cell.new("│", chart.y_axis.style))
        end)
      else
        buffer
      end

    buffer =
      Enum.reduce(graph.x..(Rect.right(graph) - 1)//1, buffer, fn x, buf ->
        Buffer.put(buf, x, axis_y, Elui.Buffer.Cell.new("─", chart.x_axis.style))
      end)

    if axis_x >= 0 do
      Buffer.put(buffer, axis_x, axis_y, Elui.Buffer.Cell.new("└", chart.x_axis.style))
    else
      buffer
    end
  end

  defp draw_labels(buffer, chart, _inner, graph, y_label_width) do
    # Y labels: spread from top (max) to bottom (min)
    y_count = length(chart.y_axis.labels)

    buffer =
      chart.y_axis.labels
      |> Enum.reverse()
      |> Enum.with_index()
      |> Enum.reduce(buffer, fn {label, i}, buf ->
        y =
          if y_count > 1 do
            graph.y + round(i * (graph.height - 1) / (y_count - 1))
          else
            Rect.bottom(graph) - 1
          end

        label = %{label | alignment: :right, style: Style.patch(chart.y_axis.style, label.style)}
        {buf, _} = Buffer.set_line(buf, graph.x - 1 - y_label_width, y, label, y_label_width)
        buf
      end)

    # X labels: spread from left (min) to right (max)
    x_count = length(chart.x_axis.labels)

    chart.x_axis.labels
    |> Enum.with_index()
    |> Enum.reduce(buffer, fn {label, i}, buf ->
      width = Line.width(label)

      x =
        if x_count > 1 do
          graph.x + round(i * (graph.width - 1) / (x_count - 1)) - div(width, 2)
        else
          graph.x
        end

      x = x |> max(graph.x - 1) |> min(Rect.right(graph) - width)
      label = Elui.Text.Line.patch_style(label, chart.x_axis.style)
      {buf, _} = Buffer.set_line(buf, x, Rect.bottom(graph) + 1, label, width)
      buf
    end)
  end

  defp draw_datasets(buffer, chart, graph) do
    Enum.reduce(chart.datasets, buffer, fn dataset, buf ->
      color = dataset.style.fg || :reset

      canvas =
        Canvas.new(
          x_bounds: chart.x_axis.bounds,
          y_bounds: chart.y_axis.bounds,
          marker: dataset.marker,
          paint: fn ctx -> paint_dataset(ctx, dataset, color, chart) end
        )

      Canvas.render_into(canvas, graph, buf)
    end)
  end

  defp paint_dataset(ctx, %Dataset{graph_type: :scatter} = dataset, color, _chart) do
    Context.draw(ctx, %Shapes.Points{coords: dataset.data, color: color})
  end

  defp paint_dataset(ctx, %Dataset{graph_type: :line} = dataset, color, _chart) do
    dataset.data
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(ctx, fn [{x1, y1}, {x2, y2}], acc ->
      Context.draw(acc, %Shapes.Line{x1: x1, y1: y1, x2: x2, y2: y2, color: color})
    end)
  end

  defp paint_dataset(ctx, %Dataset{graph_type: :bar} = dataset, color, chart) do
    {y_min, _} = chart.y_axis.bounds

    Enum.reduce(dataset.data, ctx, fn {x, y}, acc ->
      Context.draw(acc, %Shapes.Line{x1: x, y1: y_min, x2: x, y2: y, color: color})
    end)
  end

  defp draw_legend(buffer, %{hidden_legend: true}, _graph), do: buffer

  defp draw_legend(buffer, chart, graph) do
    names = chart.datasets |> Enum.filter(& &1.name)

    if names == [] do
      buffer
    else
      width = names |> Enum.map(&Elui.Text.Width.of(&1.name)) |> Enum.max()
      x = Rect.right(graph) - width

      names
      |> Enum.with_index()
      |> Enum.reduce(buffer, fn {dataset, i}, buf ->
        Buffer.set_string(buf, x, graph.y + i, dataset.name, dataset.style)
      end)
    end
  end

  defp draw_titles(buffer, chart, _inner, graph) do
    buffer =
      case chart.x_axis.title do
        nil ->
          buffer

        title ->
          w = Line.width(title)
          {buf, _} = Buffer.set_line(buffer, Rect.right(graph) - w, Rect.bottom(graph), title, w)
          buf
      end

    case chart.y_axis.title do
      nil ->
        buffer

      title ->
        {buf, _} = Buffer.set_line(buffer, graph.x, graph.y, title, Line.width(title))
        buf
    end
  end

  defimpl Elui.Widget do
    def render(chart, area, buffer), do: Elui.Widgets.Chart.render_into(chart, area, buffer)
  end
end

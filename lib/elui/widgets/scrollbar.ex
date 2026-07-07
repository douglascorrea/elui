defmodule Elui.Widgets.Scrollbar.State do
  @moduledoc """
  Scroll position state for `Elui.Widgets.Scrollbar`.
  Mirrors ratatui's `ScrollbarState`.
  """

  defstruct content_length: 0, position: 0, viewport_content_length: 0

  @type t :: %__MODULE__{}

  @spec new(non_neg_integer(), Keyword.t()) :: t()
  def new(content_length, opts \\ []) do
    %__MODULE__{
      content_length: content_length,
      position: Keyword.get(opts, :position, 0),
      viewport_content_length: Keyword.get(opts, :viewport_content_length, 0)
    }
  end

  @spec position(t(), non_neg_integer()) :: t()
  def position(%__MODULE__{} = state, pos), do: %{state | position: pos}

  @spec next(t()) :: t()
  def next(%__MODULE__{} = state) do
    %{state | position: min(state.position + 1, max(state.content_length - 1, 0))}
  end

  @spec prev(t()) :: t()
  def prev(%__MODULE__{} = state), do: %{state | position: max(state.position - 1, 0)}

  @spec first(t()) :: t()
  def first(%__MODULE__{} = state), do: %{state | position: 0}

  @spec last(t()) :: t()
  def last(%__MODULE__{} = state), do: %{state | position: max(state.content_length - 1, 0)}
end

defmodule Elui.Widgets.Scrollbar do
  @moduledoc """
  A scrollbar drawn along one side of an area. Mirrors ratatui's
  `Scrollbar` / `ScrollbarState`.

  ## Example

      scrollbar = Scrollbar.new(:vertical_right)
      state = Scrollbar.State.new(100, position: 40)
      {buffer, state} = Elui.StatefulWidget.render(scrollbar, area, buffer, state)
  """

  alias Elui.Buffer
  alias Elui.Layout.Rect
  alias Elui.Style
  alias Elui.Widgets.Scrollbar.State

  defstruct orientation: :vertical_right,
            thumb_symbol: nil,
            track_symbol: nil,
            begin_symbol: nil,
            end_symbol: nil,
            style: %Style{},
            thumb_style: %Style{},
            track_style: %Style{}

  @type orientation :: :vertical_right | :vertical_left | :horizontal_bottom | :horizontal_top
  @type t :: %__MODULE__{}

  @doc """
  Creates a scrollbar for the given orientation.

  Options: `:thumb_symbol`, `:track_symbol`, `:begin_symbol`,
  `:end_symbol`, `:style`, `:thumb_style`, `:track_style`.
  """
  @spec new(orientation(), Keyword.t()) :: t()
  def new(orientation \\ :vertical_right, opts \\ []) do
    defaults =
      if orientation in [:vertical_right, :vertical_left] do
        Elui.Symbols.Scrollbar.vertical()
      else
        Elui.Symbols.Scrollbar.horizontal()
      end

    %__MODULE__{
      orientation: orientation,
      thumb_symbol: Keyword.get(opts, :thumb_symbol, defaults.thumb),
      track_symbol: Keyword.get(opts, :track_symbol, defaults.track),
      begin_symbol: Keyword.get(opts, :begin_symbol, defaults.begin),
      end_symbol: Keyword.get(opts, :end_symbol, defaults.end),
      style: Style.to_style(Keyword.get(opts, :style)),
      thumb_style: Style.to_style(Keyword.get(opts, :thumb_style)),
      track_style: Style.to_style(Keyword.get(opts, :track_style))
    }
  end

  @doc false
  def render_into(%__MODULE__{} = scrollbar, area, buffer, %State{} = state) do
    if Rect.empty?(area) or state.content_length == 0 do
      {buffer, state}
    else
      track = track_positions(scrollbar, area)
      track_len = length(track)

      arrows = ((scrollbar.begin_symbol && 1) || 0) + ((scrollbar.end_symbol && 1) || 0)
      bar_len = max(track_len - arrows, 1)

      thumb_len = max(round(bar_len * bar_len / max(state.content_length, bar_len)), 1)
      max_pos = max(state.content_length - 1, 1)
      thumb_start = round(state.position / max_pos * (bar_len - thumb_len))

      buffer =
        track
        |> Enum.with_index()
        |> Enum.reduce(buffer, fn {{x, y}, i}, buf ->
          {symbol, style} =
            cond do
              i == 0 and scrollbar.begin_symbol ->
                {scrollbar.begin_symbol, scrollbar.style}

              i == track_len - 1 and scrollbar.end_symbol ->
                {scrollbar.end_symbol, scrollbar.style}

              true ->
                bar_i = i - if(scrollbar.begin_symbol, do: 1, else: 0)

                if bar_i >= thumb_start and bar_i < thumb_start + thumb_len do
                  {scrollbar.thumb_symbol, Style.patch(scrollbar.style, scrollbar.thumb_style)}
                else
                  {scrollbar.track_symbol, Style.patch(scrollbar.style, scrollbar.track_style)}
                end
            end

          if symbol do
            Buffer.put(buf, x, y, Elui.Buffer.Cell.new(symbol, style))
          else
            buf
          end
        end)

      {buffer, state}
    end
  end

  defp track_positions(%{orientation: :vertical_right}, area) do
    x = Rect.right(area) - 1
    for y <- area.y..(Rect.bottom(area) - 1)//1, do: {x, y}
  end

  defp track_positions(%{orientation: :vertical_left}, area) do
    for y <- area.y..(Rect.bottom(area) - 1)//1, do: {area.x, y}
  end

  defp track_positions(%{orientation: :horizontal_bottom}, area) do
    y = Rect.bottom(area) - 1
    for x <- area.x..(Rect.right(area) - 1)//1, do: {x, y}
  end

  defp track_positions(%{orientation: :horizontal_top}, area) do
    for x <- area.x..(Rect.right(area) - 1)//1, do: {x, area.y}
  end

  defimpl Elui.StatefulWidget do
    def render(scrollbar, area, buffer, state) do
      Elui.Widgets.Scrollbar.render_into(scrollbar, area, buffer, state)
    end
  end
end

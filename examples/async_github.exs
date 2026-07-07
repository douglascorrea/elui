Code.require_file("support/ratatui_port.exs", __DIR__)

# Async GitHub demo: an Elui.App example that receives a message from a
# background task and renders the result in a stateful table.
#
# Run with:
#
#     mix run examples/async_github.exs

defmodule Examples.AsyncGithub do
  @behaviour Elui.App

  alias Elui.{Frame, Layout}
  alias Elui.Text.Line
  alias Elui.Widgets.{Block, Paragraph, Table}
  alias Elui.Widgets.Table.Row

  @impl true
  def init(_opts) do
    parent = self()

    Task.start(fn ->
      Process.sleep(450)
      send(parent, {:github_prs, Examples.Support.sample_pull_requests()})
    end)

    %{status: :loading, spinner: 0, prs: [], table_state: Table.State.new(selected: 0)}
  end

  @impl true
  def update(model, event) do
    cond do
      Examples.Support.quit?(event) ->
        :quit

      Examples.Support.key?(event, [:down, {:char, "j"}]) ->
        {:ok, %{model | table_state: Table.State.select_next(model.table_state, length(model.prs))}}

      Examples.Support.key?(event, [:up, {:char, "k"}]) ->
        {:ok, %{model | table_state: Table.State.select_previous(model.table_state, length(model.prs))}}

      event == :tick ->
        {:ok, %{model | spinner: rem(model.spinner + 1, 4)}}

      match?({:message, {:github_prs, _prs}}, event) ->
        {:message, {:github_prs, prs}} = event
        {:ok, %{model | status: :ready, prs: prs}}

      true ->
        {:ok, model}
    end
  end

  @impl true
  def view(model, frame) do
    [title, body, footer] =
      Layout.vertical([{:length, 2}, {:fill, 1}, {:length, 1}])
      |> Layout.split(Frame.area(frame))

    frame =
      Examples.Support.render_header(
        frame,
        title,
        "Ratatui async GitHub port",
        "j/k scroll, q quit"
      )

    frame =
      case model.status do
        :loading ->
          Frame.render_widget(
            frame,
            Paragraph.new("#{Enum.at(~w(| / - \\\\), model.spinner)} fetching pull requests...",
              alignment: :center,
              block: Block.bordered(title: "ratatui/ratatui")
            ),
            body
          )

        :ready ->
          render_table(frame, body, model)
      end

    Examples.Support.render_footer(frame, footer, "background task -> app message -> stateful table")
  end

  defp render_table(frame, area, model) do
    rows = Enum.map(model.prs, fn pr -> Row.new(Tuple.to_list(pr)) end)

    table =
      Table.new(rows, [{:length, 8}, {:fill, 2}, {:length, 12}, {:length, 16}],
        header:
          Row.new(["PR", "Title", "Author", "Updated"],
            style: [fg: :yellow, add_modifier: [:bold]]
          ),
        block: Block.bordered(title: Line.new("Pull requests", style: [fg: :cyan])),
        row_highlight_style: [bg: :blue],
        highlight_symbol: "> "
      )

    {frame, _state} = Frame.render_stateful_widget(frame, table, area, model.table_state)
    frame
  end
end

Examples.Support.run(Examples.AsyncGithub, tick_rate: 120)

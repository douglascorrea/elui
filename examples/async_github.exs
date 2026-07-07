Code.require_file("support/ratatui_port.exs", __DIR__)

# Async GitHub demo: fetches recent commits from elixir-lang/elixir in a
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

  @repo "elixir-lang/elixir"
  @commits_url "https://api.github.com/repos/#{@repo}/commits?per_page=20"
  @http_otp_apps [:asn1, :crypto, :public_key, :ssl, :inets]

  @impl true
  def init(_opts) do
    parent = self()

    spawn(fn -> send(parent, {:github_commits, safe_fetch_commits()}) end)

    %{
      status: :loading,
      spinner: 0,
      commits: [],
      error: nil,
      table_state: Table.State.new(selected: 0)
    }
  end

  @impl true
  def update(model, event) do
    cond do
      Examples.Support.quit?(event) ->
        :quit

      Examples.Support.key?(event, [:down, {:char, "j"}]) ->
        {:ok,
         %{model | table_state: Table.State.select_next(model.table_state, length(model.commits))}}

      Examples.Support.key?(event, [:up, {:char, "k"}]) ->
        {:ok,
         %{
           model
           | table_state: Table.State.select_previous(model.table_state, length(model.commits))
         }}

      event == :tick ->
        {:ok, %{model | spinner: rem(model.spinner + 1, 4)}}

      match?({:message, {:github_commits, {:ok, _commits}}}, event) ->
        {:message, {:github_commits, {:ok, commits}}} = event
        {:ok, %{model | status: :ready, commits: commits, error: nil}}

      match?({:message, {:github_commits, {:error, _reason}}}, event) ->
        {:message, {:github_commits, {:error, reason}}} = event
        {:ok, %{model | status: :error, error: reason}}

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
        "#{@repo} commits",
        "j/k scroll, q quit"
      )

    frame =
      case model.status do
        :loading ->
          Frame.render_widget(
            frame,
            Paragraph.new("#{Enum.at(~w(| / - \\\\), model.spinner)} fetching recent commits...",
              alignment: :center,
              block: Block.bordered(title: @repo)
            ),
            body
          )

        :ready ->
          render_table(frame, body, model)

        :error ->
          Frame.render_widget(
            frame,
            Paragraph.new("Could not fetch commits from GitHub.\n\n#{model.error}",
              alignment: :center,
              wrap: [trim: true],
              block: Block.bordered(title: "Fetch error", border_style: [fg: :light_red])
            ),
            body
          )
      end

    Examples.Support.render_footer(
      frame,
      footer,
      "#{@commits_url} · background task -> app message"
    )
  end

  defp render_table(frame, area, model) do
    rows = Enum.map(model.commits, fn commit -> Row.new(Tuple.to_list(commit)) end)

    table =
      Table.new(rows, [{:length, 9}, {:fill, 2}, {:length, 20}, {:length, 20}],
        header:
          Row.new(["SHA", "Message", "Author", "Date"],
            style: [fg: :yellow, add_modifier: [:bold]]
          ),
        block: Block.bordered(title: Line.new("Recent commits", style: [fg: :cyan])),
        row_highlight_style: [bg: :blue],
        highlight_symbol: "> "
      )

    {frame, _state} = Frame.render_stateful_widget(frame, table, area, model.table_state)
    frame
  end

  defp fetch_commits do
    with :ok <- ensure_http_started(),
         {:ok, body} <- request_commits(),
         {:ok, commits} <- JSON.decode(body) do
      {:ok, Enum.map(commits, &commit_row/1)}
    else
      {:error, reason} -> {:error, format_error(reason)}
      other -> {:error, format_error(other)}
    end
  end

  defp safe_fetch_commits do
    fetch_commits()
  rescue
    exception ->
      {:error, Exception.message(exception)}
  catch
    kind, reason ->
      {:error, format_error({kind, reason})}
  end

  defp ensure_http_started do
    with :ok <- ensure_otp_app_code_paths(@http_otp_apps),
         {:ok, _} <- Application.ensure_all_started(:inets),
         {:ok, _} <- Application.ensure_all_started(:ssl) do
      :ok
    end
  end

  defp ensure_otp_app_code_paths(apps) do
    Enum.reduce_while(apps, :ok, fn app, :ok ->
      case ensure_otp_app_code_path(app) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp ensure_otp_app_code_path(app) do
    with {:ok, ebin_dir} <- otp_app_ebin_dir(app) do
      case :code.add_patha(ebin_dir) do
        true -> :ok
        {:error, reason} -> {:error, "could not load #{app} code path: #{inspect(reason)}"}
      end
    end
  end

  defp otp_app_ebin_dir(app) do
    case :code.lib_dir(app) do
      lib_dir when is_list(lib_dir) ->
        {:ok, :filename.join(lib_dir, ~c"ebin")}

      {:error, _reason} ->
        app
        |> otp_app_ebin_dir_pattern()
        |> Path.wildcard()
        |> Enum.sort(:desc)
        |> case do
          [ebin_dir | _] -> {:ok, String.to_charlist(ebin_dir)}
          [] -> {:error, "could not find #{app} code path"}
        end
    end
  end

  defp otp_app_ebin_dir_pattern(app) do
    Path.join([to_string(:code.lib_dir()), "#{app}-*", "ebin"])
  end

  defp request_commits do
    headers = [
      {~c"user-agent", ~c"elui-async-github-example"},
      {~c"accept", ~c"application/vnd.github+json"}
    ]

    case safe_http_request(
           :get,
           {String.to_charlist(@commits_url), headers},
           [timeout: 10_000],
           body_format: :binary
         ) do
      {:ok, {{_version, 200, _reason}, _headers, body}} ->
        {:ok, body}

      {:ok, {{_version, status, reason}, _headers, body}} ->
        {:error, "GitHub returned HTTP #{status} #{reason}: #{String.slice(body, 0, 160)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp safe_http_request(method, request, http_options, options) do
    :httpc.request(method, request, http_options, options)
  rescue
    exception ->
      {:error, Exception.message(exception)}
  catch
    kind, reason ->
      {:error, {kind, reason}}
  end

  defp commit_row(%{"sha" => sha, "commit" => commit} = payload) do
    details = commit || %{}

    author =
      get_in(details, ["author", "name"]) || get_in(payload, ["author", "login"]) || "unknown"

    date = details |> get_in(["author", "date"]) |> format_date()
    message = details |> Map.get("message", "") |> first_line()

    {String.slice(sha, 0, 8), message, author, date}
  end

  defp commit_row(_payload), do: {"unknown", "unparseable commit", "unknown", ""}

  defp first_line(message) do
    message
    |> to_string()
    |> String.split("\n", parts: 2)
    |> hd()
  end

  defp format_date(nil), do: ""

  defp format_date(date) do
    date
    |> String.replace("T", " ")
    |> String.replace("Z", " UTC")
  end

  defp format_error(reason) when is_binary(reason), do: reason

  defp format_error({kind, reason}) when kind in [:error, :exit, :throw],
    do: "#{kind}: #{inspect(reason)}"

  defp format_error(reason), do: inspect(reason)
end

Examples.Support.run(Examples.AsyncGithub, tick_rate: 120)

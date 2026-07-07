Code.require_file("support/ratatui_port.exs", __DIR__)

# BEAM Lab: a live Elui dashboard backed by normal OTP processes.
#
# Run with:
#
#     mix run examples/beam_lab.exs
#
# Optional remote-node companion, after pressing `n` in the UI:
#
#     iex --sname elui_peer --cookie elui_beam_lab -S mix

defmodule Examples.BeamLab.Supervisor do
  use Supervisor

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    app_pid = Keyword.fetch!(opts, :app_pid)

    children = [
      {Examples.BeamLab.PulseServer, app_pid: app_pid},
      {Examples.BeamLab.NodeServer, app_pid: app_pid},
      {Examples.BeamLab.InternetStream, app_pid: app_pid}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

defmodule Examples.BeamLab.PulseServer do
  use GenServer

  @interval 1_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    state = %{
      app_pid: Keyword.fetch!(opts, :app_pid),
      tick: 0,
      started_at: System.monotonic_time(:millisecond),
      last_reductions: total_reductions(),
      history: []
    }

    send(self(), :pulse)
    {:ok, state}
  end

  @impl true
  def handle_info(:pulse, state) do
    now = System.monotonic_time(:millisecond)
    total_reductions = total_reductions()
    reduction_delta = max(total_reductions - state.last_reductions, 0)
    history = Enum.take(state.history ++ [reduction_delta], -36)

    pulse = %{
      tick: state.tick + 1,
      uptime_ms: now - state.started_at,
      memory_mb: (:erlang.memory(:total) / 1_048_576) |> Float.round(1),
      processes: :erlang.system_info(:process_count),
      schedulers: :erlang.system_info(:schedulers_online),
      run_queue: :erlang.statistics(:run_queue),
      mailbox: self() |> Process.info(:message_queue_len) |> elem(1),
      reductions: reduction_delta,
      history: history
    }

    send(state.app_pid, {:beam_lab, {:pulse, pulse}})
    Process.send_after(self(), :pulse, @interval)

    {:noreply, %{state | tick: pulse.tick, last_reductions: total_reductions, history: history}}
  end

  defp total_reductions do
    :erlang.statistics(:reductions) |> elem(0)
  end
end

defmodule Examples.BeamLab.NodeServer do
  use GenServer

  @cookie :elui_beam_lab
  @poll_interval 1_500

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    host = hostname()

    state = %{
      app_pid: Keyword.fetch!(opts, :app_pid),
      local_name: :"elui_beam_lab_#{System.unique_integer([:positive])}",
      target: :"elui_peer@#{host}",
      last_action: "press n to start local distribution",
      last_error: nil
    }

    send(self(), :poll)
    {:ok, state}
  end

  @impl true
  def handle_cast(:start_distribution, state) do
    {:noreply, state |> start_distribution() |> emit_snapshot()}
  end

  def handle_cast(:connect_target, state) do
    state = if Node.alive?(), do: state, else: start_distribution(state)

    state =
      if Node.alive?() do
        Node.set_cookie(state.target, @cookie)

        case Node.connect(state.target) do
          true ->
            %{state | last_action: "connected to #{state.target}", last_error: nil}

          false ->
            %{
              state
              | last_action: "connect attempted",
                last_error: "could not connect to #{state.target}"
            }

          :ignored ->
            %{
              state
              | last_action: "connect ignored",
                last_error: "local node is not distributed"
            }
        end
      else
        state
      end

    {:noreply, emit_snapshot(state)}
  end

  def handle_cast(:disconnect_all, state) do
    Enum.each(Node.list(), &Node.disconnect/1)
    {:noreply, emit_snapshot(%{state | last_action: "disconnect sent to all visible nodes"})}
  end

  @impl true
  def handle_info(:poll, state) do
    Process.send_after(self(), :poll, @poll_interval)
    {:noreply, emit_snapshot(state)}
  end

  def handle_info({:nodeup, node}, state) do
    {:noreply, emit_snapshot(%{state | last_action: "node up: #{node}", last_error: nil})}
  end

  def handle_info({:nodedown, node}, state) do
    {:noreply, emit_snapshot(%{state | last_action: "node down: #{node}"})}
  end

  defp start_distribution(state) do
    cond do
      Node.alive?() ->
        enable_node_monitor()
        Node.set_cookie(@cookie)
        %{state | last_action: "already running as #{Node.self()}", last_error: nil}

      true ->
        with :ok <- start_epmd(),
             {:ok, _pid} <- Node.start(state.local_name, :shortnames) do
          enable_node_monitor()
          Node.set_cookie(@cookie)
          %{state | last_action: "started #{Node.self()} with cookie #{@cookie}", last_error: nil}
        else
          {:error, reason} ->
            %{
              state
              | last_action: "start distribution failed",
                last_error: format_error(reason)
            }
        end
    end
  end

  defp emit_snapshot(state) do
    send(state.app_pid, {:beam_lab, {:node, snapshot(state)}})
    state
  end

  defp snapshot(state) do
    connected = Node.list()

    %{
      alive?: Node.alive?(),
      self: Node.self(),
      cookie: @cookie,
      target: state.target,
      command: "iex --sname elui_peer --cookie #{@cookie} -S mix",
      connected: connected,
      known: safe_node_list(:known),
      remote_probe: remote_probe(state.target, connected),
      last_action: state.last_action,
      last_error: state.last_error
    }
  end

  defp safe_node_list(type) do
    Node.list(type)
  rescue
    _ -> []
  end

  defp remote_probe(target, connected) do
    if target in connected do
      otp = :rpc.call(target, :erlang, :system_info, [:otp_release], 500)
      processes = :rpc.call(target, :erlang, :system_info, [:process_count], 500)

      "remote OTP #{inspect(otp)}, processes #{inspect(processes)}"
    else
      "not connected"
    end
  end

  defp start_epmd do
    case System.find_executable("epmd") do
      nil ->
        {:error, "epmd executable not found"}

      epmd ->
        case System.cmd(epmd, ["-daemon"], stderr_to_stdout: true) do
          {_output, 0} -> :ok
          {output, status} -> {:error, "epmd exited #{status}: #{String.trim(output)}"}
        end
    end
  end

  defp enable_node_monitor do
    :net_kernel.monitor_nodes(true)
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp hostname do
    case :inet.gethostname() do
      {:ok, host} -> List.to_string(host)
      _ -> "localhost"
    end
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end

defmodule Examples.BeamLab.InternetStream do
  use GenServer

  @url "https://api.github.com/repos/elixir-lang/elixir/events?per_page=12"
  @refresh_interval 30_000
  @emit_interval 650
  @http_otp_apps [:asn1, :crypto, :public_key, :ssl, :inets]

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    state = %{
      app_pid: Keyword.fetch!(opts, :app_pid),
      status: :idle,
      queue: [],
      feed: [],
      bytes: 0,
      last_error: nil,
      last_fetch: nil,
      seq: 0
    }

    Process.send_after(self(), :refresh, 100)
    {:ok, state}
  end

  @impl true
  def handle_cast(:refresh, state) do
    {:noreply, start_fetch(state)}
  end

  @impl true
  def handle_info(:refresh, state) do
    {:noreply, start_fetch(state)}
  end

  def handle_info({:events_fetched, {:ok, events, bytes}}, state) do
    state = %{
      state
      | status: :streaming,
        queue: events,
        bytes: bytes,
        last_error: nil,
        last_fetch: now_time()
    }

    Process.send_after(self(), :emit_next, @emit_interval)
    {:noreply, emit_snapshot(state)}
  end

  def handle_info({:events_fetched, {:error, reason}}, state) do
    state = %{state | status: :error, last_error: reason, last_fetch: now_time()}
    {:noreply, emit_snapshot(state)}
  end

  def handle_info(:emit_next, %{queue: [event | rest]} = state) do
    state = %{
      state
      | status: if(rest == [], do: :idle, else: :streaming),
        queue: rest,
        seq: state.seq + 1,
        feed: Enum.take([Map.put(event, :seq, state.seq + 1) | state.feed], 12)
    }

    if rest != [], do: Process.send_after(self(), :emit_next, @emit_interval)
    {:noreply, emit_snapshot(state)}
  end

  def handle_info(:emit_next, state) do
    {:noreply, emit_snapshot(%{state | status: :idle})}
  end

  defp start_fetch(%{status: :fetching} = state), do: state

  defp start_fetch(state) do
    server = self()
    spawn(fn -> send(server, {:events_fetched, safe_fetch_events()}) end)
    Process.send_after(self(), :refresh, @refresh_interval)
    emit_snapshot(%{state | status: :fetching, last_error: nil})
  end

  defp safe_fetch_events do
    fetch_events()
  rescue
    exception ->
      {:error, Exception.message(exception)}
  catch
    kind, reason ->
      {:error, "#{kind}: #{inspect(reason)}"}
  end

  defp fetch_events do
    with :ok <- ensure_http_started(),
         {:ok, body} <- request_events(),
         {:ok, events} <- decode_events(body) do
      {:ok, events, byte_size(body)}
    else
      {:error, reason} -> {:error, format_error(reason)}
      other -> {:error, format_error(other)}
    end
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

  defp request_events do
    headers = [
      {~c"user-agent", ~c"elui-beam-lab-example"},
      {~c"accept", ~c"application/vnd.github+json"}
    ]

    case safe_http_request(
           :get,
           {String.to_charlist(@url), headers},
           [timeout: 12_000],
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

  defp decode_events(body) do
    case JSON.decode(body) do
      {:ok, events} when is_list(events) ->
        {:ok, Enum.map(events, &event_row/1)}

      {:ok, %{"message" => message}} ->
        {:error, message}

      {:ok, other} ->
        {:error, "unexpected payload: #{inspect(other, limit: 3)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp event_row(%{"type" => type, "actor" => actor, "repo" => repo} = event) do
    payload = Map.get(event, "payload") || %{}

    %{
      type: type,
      actor: Map.get(actor || %{}, "login", "unknown"),
      repo: repo |> Map.get("name", "unknown") |> short_repo(),
      detail: event_detail(type, payload),
      at: event |> Map.get("created_at") |> format_time()
    }
  end

  defp event_row(_event) do
    %{type: "Unknown", actor: "unknown", repo: "unknown", detail: "unparseable", at: ""}
  end

  defp event_detail("PushEvent", %{"commits" => commits}) when is_list(commits) do
    "#{length(commits)} commits"
  end

  defp event_detail(_type, %{"ref" => ref}) when is_binary(ref), do: ref
  defp event_detail(type, _payload), do: type

  defp short_repo(repo) do
    repo
    |> to_string()
    |> String.replace_prefix("elixir-lang/", "")
  end

  defp format_time(nil), do: ""

  defp format_time(value) do
    value
    |> String.replace("T", " ")
    |> String.replace("Z", "")
  end

  defp emit_snapshot(state) do
    send(state.app_pid, {:beam_lab, {:stream, snapshot(state)}})
    state
  end

  defp snapshot(state) do
    %{
      status: state.status,
      feed: state.feed,
      bytes: state.bytes,
      last_error: state.last_error,
      last_fetch: state.last_fetch,
      queued: length(state.queue),
      url: @url
    }
  end

  defp now_time do
    {{year, month, day}, {hour, minute, second}} = :calendar.local_time()

    [year, month, day, hour, minute, second]
    |> Enum.map(&Integer.to_string/1)
    |> Enum.map(&String.pad_leading(&1, 2, "0"))
    |> then(fn [y, mo, d, h, mi, s] -> "#{y}-#{mo}-#{d} #{h}:#{mi}:#{s}" end)
  end

  defp format_error(reason) when is_binary(reason), do: reason

  defp format_error({kind, reason}) when kind in [:error, :exit, :throw],
    do: "#{kind}: #{inspect(reason)}"

  defp format_error(reason), do: inspect(reason)
end

defmodule Examples.BeamLab do
  @behaviour Elui.App

  alias Elui.{Frame, Layout}
  alias Elui.Text.{Line, Span}
  alias Elui.Widgets.{Block, Gauge, Paragraph, Sparkline, Table}
  alias Elui.Widgets.Table.Row

  @blank_pulse %{
    tick: 0,
    uptime_ms: 0,
    memory_mb: 0.0,
    processes: 0,
    schedulers: 1,
    run_queue: 0,
    mailbox: 0,
    reductions: 0,
    history: []
  }

  @blank_node %{
    alive?: false,
    self: :nonode@nohost,
    cookie: :elui_beam_lab,
    target: :unknown,
    command: "iex --sname elui_peer --cookie elui_beam_lab -S mix",
    connected: [],
    known: [],
    remote_probe: "not connected",
    last_action: "waiting for NodeServer",
    last_error: nil
  }

  @blank_stream %{
    status: :idle,
    feed: [],
    bytes: 0,
    last_error: nil,
    last_fetch: nil,
    queued: 0,
    url: ""
  }

  @impl true
  def init(_opts) do
    parent = self()
    {:ok, supervisor} = Examples.BeamLab.Supervisor.start_link(app_pid: parent)
    Process.monitor(supervisor)

    %{
      supervisor: supervisor,
      children: child_pids(supervisor),
      pulse: @blank_pulse,
      node: @blank_node,
      stream: @blank_stream,
      log: ["BEAM Lab supervision tree started"]
    }
  end

  @impl true
  def update(model, {:message, {:beam_lab, {:pulse, pulse}}}) do
    {:ok, %{model | pulse: pulse}}
  end

  def update(model, {:message, {:beam_lab, {:node, node}}}) do
    {:ok, %{model | node: node} |> put_log(node.last_action)}
  end

  def update(model, {:message, {:beam_lab, {:stream, stream}}}) do
    {:ok, %{model | stream: stream}}
  end

  def update(model, {:message, {:DOWN, _ref, :process, supervisor, reason}})
      when supervisor == model.supervisor do
    {:ok,
     %{model | supervisor: nil, children: %{}}
     |> put_log("supervisor stopped: #{inspect(reason)}")}
  end

  def update(model, event) do
    cond do
      Examples.Support.quit?(event) ->
        stop_supervisor(model)
        {:quit, model}

      Examples.Support.key?(event, {:char, "n"}) ->
        cast_child(model, Examples.BeamLab.NodeServer, :start_distribution)
        {:ok, put_log(model, "requested local node start")}

      Examples.Support.key?(event, {:char, "c"}) ->
        cast_child(model, Examples.BeamLab.NodeServer, :connect_target)
        {:ok, put_log(model, "requested remote node connect")}

      Examples.Support.key?(event, {:char, "d"}) ->
        cast_child(model, Examples.BeamLab.NodeServer, :disconnect_all)
        {:ok, put_log(model, "requested node disconnect")}

      Examples.Support.key?(event, {:char, "f"}) ->
        cast_child(model, Examples.BeamLab.InternetStream, :refresh)
        {:ok, put_log(model, "requested internet stream refresh")}

      true ->
        {:ok, model}
    end
  end

  @impl true
  def view(model, frame) do
    [header, body, footer] =
      Layout.vertical([{:length, 2}, {:fill, 1}, {:length, 1}])
      |> Layout.split(Frame.area(frame))

    frame =
      Examples.Support.render_header(
        frame,
        header,
        "BEAM Lab",
        "q quit | n node | c connect | d disconnect | f fetch"
      )

    [top, stream] =
      Layout.vertical([{:length, 15}, {:fill, 1}], spacing: 1)
      |> Layout.split(body)

    [tree, runtime, nodes] =
      Layout.horizontal([{:percentage, 36}, {:percentage, 32}, {:percentage, 32}], spacing: 1)
      |> Layout.split(top)

    frame
    |> render_tree(tree, model)
    |> render_runtime(runtime, model)
    |> render_nodes(nodes, model)
    |> render_stream(stream, model)
    |> Examples.Support.render_footer(
      footer,
      "OTP supervision + GenServer messages + local/remote BEAM nodes + GitHub event stream"
    )
  end

  defp render_tree(frame, area, model) do
    lines = [
      Line.new([
        Span.new("Supervisor: ", fg: :dark_gray),
        Span.new(pid_text(model.supervisor), fg: :yellow, add_modifier: [:bold])
      ]),
      Line.new("Strategy: one_for_one"),
      Line.new(""),
      Line.new("Children", style: [fg: :cyan, add_modifier: [:bold]])
    ]

    child_lines =
      supervisor_children(model.supervisor)
      |> Enum.map(fn {id, pid, type, _modules} ->
        Line.new([
          Span.new("|-- ", fg: :dark_gray),
          Span.new(module_name(id), fg: :light_green),
          Span.new(" #{pid_text(pid)} ", fg: :dark_gray),
          Span.new(to_string(type), fg: :yellow)
        ])
      end)

    app_lines =
      started_apps()
      |> Enum.map(fn {app, version} ->
        Line.new([
          Span.new("app ", fg: :dark_gray),
          Span.new(to_string(app), fg: :light_blue),
          Span.new(" #{version}", fg: :dark_gray)
        ])
      end)

    content =
      lines ++
        child_lines ++
        [Line.new(""), Line.new("Started applications", style: [fg: :cyan])] ++
        app_lines

    Frame.render_widget(
      frame,
      Paragraph.new(content,
        block: Block.bordered(title: "Supervisor / application tree", border_style: [fg: :cyan]),
        wrap: [trim: true]
      ),
      area
    )
  end

  defp render_runtime(frame, area, model) do
    [stats_area, gauge_area, spark_area] =
      Layout.vertical([{:length, 8}, {:length, 3}, {:fill, 1}])
      |> Layout.split(area)

    pulse = model.pulse

    stats = [
      Line.new([Span.new("PulseServer", fg: :light_green, add_modifier: [:bold])]),
      Line.new("tick #{pulse.tick} | uptime #{format_duration(pulse.uptime_ms)}"),
      Line.new("processes #{pulse.processes} | schedulers #{pulse.schedulers}"),
      Line.new("memory #{pulse.memory_mb} MB | mailbox #{pulse.mailbox}"),
      Line.new("run queue #{pulse.run_queue} | reductions +#{pulse.reductions}")
    ]

    frame =
      Frame.render_widget(
        frame,
        Paragraph.new(stats,
          block: Block.bordered(title: "GenServer + OTP runtime", border_style: [fg: :green]),
          wrap: [trim: true]
        ),
        stats_area
      )

    queue_ratio = min(pulse.run_queue / max(pulse.schedulers, 1), 1.0)

    frame =
      Frame.render_widget(
        frame,
        Gauge.new(queue_ratio,
          block: Block.bordered(title: "Run queue / schedulers"),
          gauge_style: [fg: gauge_color(queue_ratio)],
          label: "#{pulse.run_queue}/#{pulse.schedulers}"
        ),
        gauge_area
      )

    Frame.render_widget(
      frame,
      Sparkline.new(pulse.history,
        block: Block.bordered(title: "Reduction bursts"),
        style: [fg: :yellow]
      ),
      spark_area
    )
  end

  defp render_nodes(frame, area, model) do
    node = model.node

    lines = [
      Line.new([
        Span.new("local: ", fg: :dark_gray),
        Span.new(to_string(node.self), fg: if(node.alive?, do: :light_green, else: :light_red))
      ]),
      Line.new("cookie: #{node.cookie}"),
      Line.new("target: #{node.target}"),
      Line.new("connected: #{format_nodes(node.connected)}"),
      Line.new("known: #{format_nodes(node.known)}"),
      Line.new("probe: #{node.remote_probe}"),
      Line.new(""),
      Line.new("remote helper", style: [fg: :cyan, add_modifier: [:bold]]),
      Line.new(node.command),
      Line.new(""),
      Line.new("last: #{node.last_action}", style: [fg: :dark_gray])
    ]

    lines =
      if node.last_error do
        lines ++ [Line.new("error: #{node.last_error}", style: [fg: :light_red])]
      else
        lines
      end

    Frame.render_widget(
      frame,
      Paragraph.new(lines,
        block: Block.bordered(title: "BEAM nodes / remote nodes", border_style: [fg: :magenta]),
        wrap: [trim: true]
      ),
      area
    )
  end

  defp render_stream(frame, area, model) do
    [table_area, log_area] =
      Layout.vertical([{:fill, 1}, {:length, 5}], spacing: 1)
      |> Layout.split(area)

    stream = model.stream

    rows =
      stream.feed
      |> Enum.map(fn event ->
        Row.new([
          to_string(event.seq),
          event.type,
          event.actor,
          event.repo,
          event.detail,
          event.at
        ])
      end)

    table =
      Table.new(
        rows,
        [{:length, 4}, {:length, 14}, {:length, 18}, {:length, 14}, {:fill, 1}, {:length, 19}],
        header:
          Row.new(["#", "Type", "Actor", "Repo", "Detail", "At"],
            style: [fg: :yellow, add_modifier: [:bold]]
          ),
        block:
          Block.bordered(
            title:
              Line.new("Internet stream: GitHub events (#{stream.status})", style: [fg: :cyan]),
            border_style: [fg: :blue]
          ),
        row_highlight_style: [bg: :blue]
      )

    frame = Frame.render_widget(frame, table, table_area)

    status_lines = [
      Line.new("url: #{stream.url}", style: [fg: :dark_gray]),
      Line.new(
        "last fetch: #{stream.last_fetch || "pending"} | bytes: #{stream.bytes} | queued: #{stream.queued}"
      ),
      Line.new("log: #{Enum.join(model.log, " | ")}", style: [fg: :dark_gray])
    ]

    status_lines =
      if stream.last_error do
        status_lines ++ [Line.new("stream error: #{stream.last_error}", style: [fg: :light_red])]
      else
        status_lines
      end

    Frame.render_widget(
      frame,
      Paragraph.new(status_lines,
        block: Block.bordered(title: "Signals", border_style: [fg: :dark_gray]),
        wrap: [trim: true]
      ),
      log_area
    )
  end

  defp child_pids(supervisor) do
    supervisor
    |> Supervisor.which_children()
    |> Map.new(fn {id, pid, _type, _modules} -> {id, pid} end)
  end

  defp supervisor_children(nil), do: []

  defp supervisor_children(supervisor) do
    Supervisor.which_children(supervisor)
  rescue
    _ -> []
  end

  defp started_apps do
    Application.started_applications()
    |> Enum.sort_by(fn {app, _description, _version} -> app end)
    |> Enum.take(5)
    |> Enum.map(fn {app, _description, version} -> {app, to_string(version)} end)
  end

  defp cast_child(model, module, message) do
    case Map.get(model.children, module) do
      pid when is_pid(pid) -> GenServer.cast(pid, message)
      _ -> :ok
    end
  end

  defp stop_supervisor(%{supervisor: supervisor}) when is_pid(supervisor) do
    if Process.alive?(supervisor), do: Supervisor.stop(supervisor)
  catch
    _, _ -> :ok
  end

  defp stop_supervisor(_model), do: :ok

  defp put_log(%{log: [message | _]} = model, message) when is_binary(message), do: model

  defp put_log(model, message) when is_binary(message) do
    %{model | log: Enum.take([message | model.log], 3)}
  end

  defp put_log(model, _message), do: model

  defp pid_text(pid) when is_pid(pid), do: inspect(pid)
  defp pid_text(nil), do: "stopped"
  defp pid_text(other), do: inspect(other)

  defp module_name(module) when is_atom(module) do
    module
    |> Module.split()
    |> List.last()
  rescue
    _ -> inspect(module)
  end

  defp module_name(other), do: inspect(other)

  defp format_nodes([]), do: "none"
  defp format_nodes(nodes), do: nodes |> Enum.map(&to_string/1) |> Enum.join(", ")

  defp format_duration(ms) do
    seconds = div(ms, 1_000)
    minutes = div(seconds, 60)
    seconds = rem(seconds, 60)

    if minutes > 0, do: "#{minutes}m #{seconds}s", else: "#{seconds}s"
  end

  defp gauge_color(ratio) when ratio >= 0.85, do: :light_red
  defp gauge_color(ratio) when ratio >= 0.55, do: :yellow
  defp gauge_color(_ratio), do: :green
end

Examples.Support.run(Examples.BeamLab, tick_rate: 120)

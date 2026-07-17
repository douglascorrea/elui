defmodule Elui.Input.Session do
  @moduledoc "Resources owned by a running `Elui.Input` reader."

  defstruct reader: nil, parser: nil, terminal_mode: nil, mouse?: false

  @type t :: %__MODULE__{
          reader: pid(),
          parser: pid(),
          terminal_mode: String.t() | nil,
          mouse?: boolean()
        }
end

defmodule Elui.Input do
  @moduledoc """
  Raw-mode keyboard input.

  Puts the terminal in raw mode (no line buffering, no echo) and
  delivers parsed key events as messages to a subscriber process:

      {:elui_event, {:key, key, modifiers}}

  where `key` is one of:

    * `{:char, "a"}` - a printable character
    * `:enter`, `:tab`, `:backspace`, `:esc`, `:space`
    * `:up`, `:down`, `:left`, `:right`
    * `:home`, `:end`, `:page_up`, `:page_down`, `:insert`, `:delete`
    * `{:f, 1..12}` - function keys

  and `modifiers` is a list that may contain `:ctrl` and `:alt`.

  When mouse capture is enabled, mouse events are delivered as:

      {:elui_event, {:mouse, kind, x, y, modifiers}}

  where `kind` is `{:down, button}`, `{:up, button}`, `{:drag, button}`,
  `:move`, `:scroll_up` or `:scroll_down`. Coordinates are zero-based.

  This plays the role of ratatui's event backends (crossterm events).
  """

  alias Elui.Input.Session

  @doc """
  Enables raw mode and starts reading keys, sending events to
  `subscriber`. Returns a session to pass to `stop/1`.
  """
  @spec start(pid(), Keyword.t()) :: Session.t()
  def start(subscriber \\ self(), opts \\ []) do
    terminal_mode = enable_raw_mode()
    mouse? = Keyword.get(opts, :mouse, false)
    if mouse?, do: enable_mouse_capture()
    parser = spawn_link(fn -> parse_loop(subscriber, []) end)
    reader = spawn_link(fn -> read_loop(parser) end)

    %Session{
      reader: reader,
      parser: parser,
      terminal_mode: terminal_mode,
      mouse?: mouse?
    }
  end

  @doc "Stops an input session and restores its exact prior terminal mode."
  @spec stop(Session.t()) :: :ok
  def stop(%Session{} = session) do
    Enum.each([session.reader, session.parser], fn pid ->
      if is_pid(pid) and Process.alive?(pid) do
        Process.unlink(pid)
        Process.exit(pid, :kill)
      end
    end)

    if session.mouse?, do: disable_mouse_capture()
    disable_raw_mode(session.terminal_mode)
  end

  @doc "Enables terminal raw mode and returns an opaque token for restoration."
  @spec enable_raw_mode() :: String.t() | nil
  def enable_raw_mode do
    terminal_mode = terminal_mode()
    set_shell_mode(:raw)
    stty(["raw", "-echo", "-ixon", "-ixoff"])
    terminal_mode
  end

  @doc "Restores the terminal to cooked (normal) mode."
  @spec disable_raw_mode(String.t() | nil) :: :ok
  def disable_raw_mode(terminal_mode \\ nil) do
    set_shell_mode(:cooked)
    restore_terminal_mode(terminal_mode)
    :ok
  end

  @doc "Enables SGR mouse capture for terminals that support it."
  @spec enable_mouse_capture() :: :ok
  def enable_mouse_capture do
    IO.write(:stdio, "\e[?1000h\e[?1002h\e[?1003h\e[?1006h")
    :ok
  rescue
    _ -> :ok
  end

  @doc "Disables mouse capture modes enabled by `enable_mouse_capture/0`."
  @spec disable_mouse_capture() :: :ok
  def disable_mouse_capture do
    IO.write(:stdio, "\e[?1006l\e[?1003l\e[?1002l\e[?1000l")
    :ok
  rescue
    _ -> :ok
  end

  defp terminal_mode do
    path =
      Path.join(
        System.tmp_dir!(),
        "elui-stty-#{System.unique_integer([:positive, :monotonic])}.state"
      )

    shell = System.find_executable("sh")

    result =
      try do
        with shell when is_binary(shell) <- shell,
             :ok <-
               run_port(shell, ["-c", "stty -g > \"$1\" 2>/dev/null", "elui-stty", path]),
             {:ok, mode} <- File.read(path) do
          String.trim(mode)
        else
          _error -> nil
        end
      rescue
        _ -> nil
      end

    File.rm(path)
    result
  end

  defp restore_terminal_mode(terminal_mode) do
    case terminal_mode do
      mode when is_binary(mode) and mode != "" ->
        stty([mode])

      _other ->
        stty(["-raw", "echo"])
    end

    :ok
  rescue
    _ -> :ok
  end

  defp set_shell_mode(mode) do
    :shell.start_interactive({:noshell, mode})
    :ok
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp stty(args) do
    case System.find_executable("stty") do
      executable when is_binary(executable) -> run_port(executable, args)
      _other -> :ok
    end
  rescue
    _ -> :ok
  end

  defp run_port(executable, args) do
    port =
      Port.open(
        {:spawn_executable, executable},
        [:nouse_stdio, :exit_status, {:args, args}]
      )

    receive do
      {^port, {:exit_status, 0}} -> :ok
      {^port, {:exit_status, _status}} -> :error
    after
      1_000 ->
        Port.close(port)
        :error
    end
  end

  # -- reader -----------------------------------------------------------------

  defp read_loop(parser) do
    case IO.getn(:stdio, "", 1) do
      :eof ->
        :ok

      {:error, _} ->
        :ok

      data ->
        send(parser, {:input, data})
        read_loop(parser)
    end
  end

  # -- parser -----------------------------------------------------------------

  # Accumulates bytes into escape sequences. A bare ESC is emitted when
  # no continuation arrives within a few milliseconds.
  defp parse_loop(subscriber, pending) do
    timeout = if pending == [], do: :infinity, else: 5

    receive do
      {:input, data} ->
        pending = pending ++ String.graphemes(data)
        pending = flush_events(subscriber, pending)
        parse_loop(subscriber, pending)
    after
      timeout ->
        # Timed out mid-sequence: emit what we have as individual keys.
        Enum.each(pending, fn ch -> emit(subscriber, parse_single(ch)) end)
        parse_loop(subscriber, [])
    end
  end

  defp flush_events(subscriber, pending) do
    case take_event(pending) do
      {:ok, event, rest} ->
        emit(subscriber, event)
        flush_events(subscriber, rest)

      :incomplete ->
        pending
    end
  end

  defp emit(subscriber, event), do: send(subscriber, {:elui_event, event})

  # ESC sequences
  defp take_event(["\e"]), do: :incomplete
  defp take_event(["\e", "["]), do: :incomplete
  defp take_event(["\e", "O"]), do: :incomplete

  defp take_event(["\e", "[" | rest]) do
    case take_csi(rest, "") do
      {:ok, event, remaining} -> {:ok, event, remaining}
      :incomplete -> :incomplete
    end
  end

  defp take_event(["\e", "O", ch | rest]) do
    key =
      case ch do
        "P" -> {:f, 1}
        "Q" -> {:f, 2}
        "R" -> {:f, 3}
        "S" -> {:f, 4}
        _ -> {:char, ch}
      end

    {:ok, {:key, key, []}, rest}
  end

  # Alt+key arrives as ESC followed by the key.
  defp take_event(["\e", ch | rest]) do
    {:key, key, mods} = parse_single(ch)
    {:ok, {:key, key, [:alt | mods]}, rest}
  end

  defp take_event([ch | rest]), do: {:ok, parse_single(ch), rest}
  defp take_event([]), do: :incomplete

  # CSI sequences: ESC [ <params> <final byte>
  defp take_csi([], _params), do: :incomplete

  defp take_csi([ch | rest], params) do
    if ch =~ ~r/[0-9;<]/ do
      take_csi(rest, params <> ch)
    else
      {:ok, csi_event(ch, params), rest}
    end
  end

  defp csi_event("A", _), do: {:key, :up, []}
  defp csi_event("B", _), do: {:key, :down, []}
  defp csi_event("C", _), do: {:key, :right, []}
  defp csi_event("D", _), do: {:key, :left, []}
  defp csi_event("H", _), do: {:key, :home, []}
  defp csi_event("F", _), do: {:key, :end, []}
  defp csi_event("Z", _), do: {:key, :back_tab, []}

  defp csi_event(final, "<" <> params) when final in ["M", "m"] do
    case parse_mouse_params(params) do
      {:ok, code, x, y} ->
        {:mouse, mouse_kind(code, final), max(x - 1, 0), max(y - 1, 0), mouse_modifiers(code)}

      :error ->
        {:key, {:unknown_csi, final}, []}
    end
  end

  defp csi_event("~", params) do
    key =
      case params |> String.split(";") |> hd() do
        "1" -> :home
        "2" -> :insert
        "3" -> :delete
        "4" -> :end
        "5" -> :page_up
        "6" -> :page_down
        "7" -> :home
        "8" -> :end
        "11" -> {:f, 1}
        "12" -> {:f, 2}
        "13" -> {:f, 3}
        "14" -> {:f, 4}
        "15" -> {:f, 5}
        "17" -> {:f, 6}
        "18" -> {:f, 7}
        "19" -> {:f, 8}
        "20" -> {:f, 9}
        "21" -> {:f, 10}
        "23" -> {:f, 11}
        "24" -> {:f, 12}
        _ -> :unknown
      end

    {:key, key, []}
  end

  defp csi_event(final, _params), do: {:key, {:unknown_csi, final}, []}

  defp parse_mouse_params(params) do
    case String.split(params, ";") do
      [code, x, y] ->
        with {code, ""} <- Integer.parse(code),
             {x, ""} <- Integer.parse(x),
             {y, ""} <- Integer.parse(y) do
          {:ok, code, x, y}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp mouse_kind(code, "m"), do: {:up, mouse_button(code)}

  defp mouse_kind(code, "M") do
    cond do
      Bitwise.band(code, 64) == 64 and rem(code, 2) == 0 -> :scroll_up
      Bitwise.band(code, 64) == 64 -> :scroll_down
      Bitwise.band(code, 32) == 32 and rem(code, 4) == 3 -> :move
      Bitwise.band(code, 32) == 32 -> {:drag, mouse_button(code)}
      true -> {:down, mouse_button(code)}
    end
  end

  defp mouse_button(code) do
    case rem(code, 4) do
      0 -> :left
      1 -> :middle
      2 -> :right
      _ -> :none
    end
  end

  defp mouse_modifiers(code) do
    []
    |> maybe_modifier(code, 4, :shift)
    |> maybe_modifier(code, 8, :alt)
    |> maybe_modifier(code, 16, :ctrl)
  end

  defp maybe_modifier(mods, code, bit, modifier) do
    if Bitwise.band(code, bit) == bit, do: [modifier | mods], else: mods
  end

  # Single characters and control codes.
  defp parse_single(ch) do
    case ch do
      "\e" -> {:key, :esc, []}
      "\r" -> {:key, :enter, []}
      "\n" -> {:key, :enter, []}
      "\t" -> {:key, :tab, []}
      " " -> {:key, :space, []}
      <<127>> -> {:key, :backspace, []}
      <<8>> -> {:key, :backspace, []}
      <<c>> when c in 1..26 -> {:key, {:char, <<c + ?a - 1>>}, [:ctrl]}
      <<c>> when c < 32 -> {:key, {:char, <<c>>}, [:ctrl]}
      other -> {:key, {:char, other}, []}
    end
  end
end

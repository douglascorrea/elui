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

  and `modifiers` is a list that may contain `:shift`, `:ctrl`, `:alt` and
  `:super`.

  Modified keys are read from CSI parameters (`ESC [ 1 ; 5 A` is Ctrl+Up) and
  from the kitty keyboard protocol's `CSI ... u` reports, which is the only
  way a terminal can distinguish Shift+Enter from Enter. Terminals send those
  reports only after an application asks for them with `CSI > 1 u`; elui
  parses them whenever they arrive. Key *release* reports are dropped, so an
  application that enables them does not see every key twice.

  When mouse capture is enabled, mouse events are delivered as:

      {:elui_event, {:mouse, kind, x, y, modifiers}}

  where `kind` is `{:down, button}`, `{:up, button}`, `{:drag, button}`,
  `:move`, `:scroll_up` or `:scroll_down`. Coordinates are zero-based.

  This plays the role of ratatui's event backends (crossterm events).
  """

  alias Elui.Input.Session

  @default_esc_timeout 25
  @default_sequence_timeout 500

  # Characters asked for per read. In `{noshell, raw}` mode the group leader
  # answers a read with whatever has arrived, up to this many, so a sequence
  # the terminal wrote in one go (a mouse report, a kitty key) reaches the
  # parser in one piece instead of a round trip per byte — between which a
  # busy group leader (writing a frame) can stall longer than `:esc_timeout`.
  @read_chunk 4096

  @doc """
  Enables raw mode and starts reading keys, sending events to
  `subscriber`. Returns a session to pass to `stop/1`.

  Options:

    * `:mouse` — enable SGR mouse capture (default `false`)
    * `:esc_timeout` — milliseconds to wait for the rest of an escape
      sequence before emitting a bare `:esc` (default
      `#{@default_esc_timeout}`). A lone ESC is indistinguishable from the
      start of `ESC [ A`, so this is a latency/robustness trade-off: too low
      and a fragmented arrow key arrives as ESC followed by literal `[A`
      (likely over ssh or a loaded machine), too high and pressing Escape
      feels sticky.
    * `:sequence_timeout` — milliseconds to wait for the rest of a sequence
      that has got past its ESC (`ESC [`, `ESC [ < 3 5 ;`, `ESC O`) before
      giving up on it (default `#{@default_sequence_timeout}`). Such a prefix
      is almost never typed, so waiting longer costs nothing; giving up early
      is what turns a slow mouse report into an Escape key plus `[<35;…M`
      typed as text. See `expire/1` for what a sequence that never completes
      becomes.
  """
  @spec start(pid(), Keyword.t()) :: Session.t()
  def start(subscriber \\ self(), opts \\ []) do
    {terminal_mode, raw_reads?} = raw_mode()
    mouse? = Keyword.get(opts, :mouse, false)

    timeouts = %{
      esc: Keyword.get(opts, :esc_timeout, @default_esc_timeout),
      sequence: Keyword.get(opts, :sequence_timeout, @default_sequence_timeout)
    }

    if mouse?, do: enable_mouse_capture()
    parser = spawn_link(fn -> parse_loop(subscriber, [], timeouts) end)
    # Without the group leader in raw mode a read of N characters waits for
    # all N, so only then is reading in chunks safe.
    chunk = if raw_reads?, do: @read_chunk, else: 1
    reader = spawn_link(fn -> read_loop(parser, chunk) end)

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
    {terminal_mode, _raw_reads?} = raw_mode()
    terminal_mode
  end

  # The prior mode, and whether the group leader switched to raw reads.
  defp raw_mode do
    terminal_mode = terminal_mode()
    raw_reads? = set_shell_mode(:raw) == :ok
    stty(["raw", "-echo", "-ixon", "-ixoff"])
    {terminal_mode, raw_reads?}
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
  rescue
    _ -> :error
  catch
    _, _ -> :error
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

  defp read_loop(parser, chunk) do
    case IO.getn(:stdio, "", chunk) do
      :eof ->
        :ok

      {:error, _} ->
        :ok

      data ->
        send(parser, {:input, data})
        read_loop(parser, chunk)
    end
  end

  @doc """
  Parses `data` into events, returning them together with any trailing
  incomplete escape sequence to prepend to the next chunk.

  The reader started by `start/2` uses this; it is public so hosts that own
  stdin themselves can reuse the parser, and so parsing is testable without a
  terminal. A lone `"\\e"` is reported as incomplete rather than as `:esc`,
  because only a timeout can tell those apart.
  """
  @spec parse(String.t()) :: {[tuple()], String.t()}
  def parse(data) do
    {events, rest} = take_events(String.graphemes(data), [])
    {events, Enum.join(rest)}
  end

  defp take_events(pending, acc) do
    case take_event(pending) do
      {:ok, :ignore, rest} -> take_events(rest, acc)
      {:ok, event, rest} -> take_events(rest, [event | acc])
      :incomplete -> {Enum.reverse(acc), pending}
    end
  end

  @doc """
  How long to wait for the rest of `pending` — the incomplete tail `parse/1`
  returned — before handing it to `expire/1`: `:infinity` for nothing,
  `esc_timeout` for a lone ESC (the Escape key, or the start of a sequence),
  `sequence_timeout` for a sequence already past its ESC.
  """
  @spec wait_time(String.t(), timeout(), timeout()) :: timeout()
  def wait_time(pending, esc_timeout, sequence_timeout \\ @default_sequence_timeout) do
    pending_wait(String.graphemes(pending), %{esc: esc_timeout, sequence: sequence_timeout})
  end

  @doc """
  The events for an incomplete tail nothing completed in time: a lone ESC is
  the Escape key, `ESC [` and `ESC O` are Alt+`[` and Alt+`O`, and a control
  sequence cut off inside its parameters (`ESC [ < 3 5 ; 1 0`, the head of a
  mouse report whose tail went missing) is dropped — never typed, because
  an Escape key followed by its characters is what stops an application.
  """
  @spec expire(String.t()) :: [tuple()]
  def expire(pending), do: expire_pending(String.graphemes(pending))

  defp pending_wait([], _timeouts), do: :infinity
  defp pending_wait(["\e"], timeouts), do: timeouts.esc
  defp pending_wait(_sequence, timeouts), do: max(timeouts.sequence, timeouts.esc)

  defp expire_pending([]), do: []
  defp expire_pending(["\e"]), do: [{:key, :esc, []}]
  defp expire_pending(["\e", ch]) when ch in ["[", "O"], do: [{:key, {:char, ch}, [:alt]}]
  defp expire_pending(["\e", "[" | _params]), do: []
  defp expire_pending(pending), do: Enum.map(pending, &parse_single/1)

  # -- parser -----------------------------------------------------------------

  # Accumulates bytes into escape sequences. What is still incomplete when
  # no more input arrives in time (`pending_wait/2`) expires (`expire/1`).
  defp parse_loop(subscriber, pending, timeouts) do
    receive do
      {:input, data} ->
        pending = pending ++ String.graphemes(data)
        pending = flush_events(subscriber, pending)
        parse_loop(subscriber, pending, timeouts)
    after
      pending_wait(pending, timeouts) ->
        Enum.each(expire_pending(pending), &emit(subscriber, &1))
        parse_loop(subscriber, [], timeouts)
    end
  end

  defp flush_events(subscriber, pending) do
    case take_event(pending) do
      # `:ignore` is a sequence that parsed cleanly but carries no key —
      # a key-release report, or a bare modifier press.
      {:ok, :ignore, rest} ->
        flush_events(subscriber, rest)

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

  # `:` separates kitty sub-parameters; `<`/`>`/`?` are private markers.
  defp take_csi([ch | rest], params) do
    if ch =~ ~r/[0-9;:<>?]/ do
      take_csi(rest, params <> ch)
    else
      {:ok, csi_event(ch, params), rest}
    end
  end

  defp csi_event("A", params), do: modified_key(:up, params)
  defp csi_event("B", params), do: modified_key(:down, params)
  defp csi_event("C", params), do: modified_key(:right, params)
  defp csi_event("D", params), do: modified_key(:left, params)
  defp csi_event("H", params), do: modified_key(:home, params)
  defp csi_event("F", params), do: modified_key(:end, params)
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

    modified_key(key, params)
  end

  # Kitty keyboard protocol:
  #
  #     CSI code[:shifted[:base]] [; mods[:event] [; text]] u
  #
  # The first field is the key on the unshifted layout, so Shift+A arrives as
  # `97;2u` — the alternate/text fields carry what was actually typed, and are
  # preferred when present so an application does not have to re-apply shift.
  defp csi_event("u", params) do
    fields = String.split(params, ";")

    cond do
      key_release?(params) -> :ignore
      true -> kitty_key_event(fields, csi_modifiers(params))
    end
  end

  defp csi_event(final, _params), do: {:key, {:unknown_csi, final}, []}

  defp kitty_key_event(fields, mods) do
    codes = fields |> hd() |> String.split(":") |> Enum.map(&parse_int/1)
    text = fields |> Enum.at(2) |> parse_text_codepoint()

    case kitty_key(codes, text, mods) do
      nil -> :ignore
      key -> {:key, key, mods}
    end
  end

  # The typed text wins, then the shifted alternate when shift is held, then
  # the base key code.
  defp kitty_key(codes, text, mods) do
    shifted = Enum.at(codes, 1)

    cond do
      is_binary(text) -> {:char, text}
      :shift in mods and is_integer(shifted) -> printable(shifted)
      true -> functional_key(hd(codes))
    end
  end

  # Keys that keep their legacy codepoint in the protocol, plus the private-use
  # block kitty assigns to keys with no codepoint. Unlisted private-use codes
  # are keypad, media and lock keys — and, in "report all keys" mode, presses
  # of the modifiers themselves; reporting those as text would type garbage,
  # so they are dropped.
  defp functional_key(code) do
    case code do
      9 -> :tab
      13 -> :enter
      27 -> :esc
      32 -> :space
      127 -> :backspace
      57_344 -> :esc
      57_345 -> :enter
      57_346 -> :tab
      57_347 -> :backspace
      57_348 -> :insert
      57_349 -> :delete
      57_350 -> :left
      57_351 -> :right
      57_352 -> :up
      57_353 -> :down
      57_354 -> :page_up
      57_355 -> :page_down
      57_356 -> :home
      57_357 -> :end
      code when is_integer(code) -> printable(code)
      _ -> nil
    end
  end

  defp printable(code) when code >= 32 and code < 57_344, do: {:char, <<code::utf8>>}
  defp printable(_code), do: nil

  defp parse_text_codepoint(nil), do: nil

  defp parse_text_codepoint(field) do
    case field |> String.split(":") |> hd() |> parse_int() do
      code when is_integer(code) and code >= 32 -> <<code::utf8>>
      _ -> nil
    end
  end

  # Event type 3 is a key release; 1 (press) and 2 (repeat) are real input.
  defp key_release?(params) do
    case params |> String.split(";") |> Enum.at(1) do
      nil -> false
      field -> field |> String.split(":") |> Enum.at(1) |> parse_int() == 3
    end
  end

  # `CSI 1 ; <mods> A`-style modifiers: the field is a 1-based bitmask, so 1
  # means "no modifiers" and 2 means shift.
  defp modified_key(key, params), do: {:key, key, csi_modifiers(params)}

  defp csi_modifiers(params) do
    with field when is_binary(field) <- params |> String.split(";") |> Enum.at(1),
         mask when is_integer(mask) <- field |> String.split(":") |> hd() |> parse_int(),
         true <- mask > 1 do
      bits = mask - 1

      []
      |> maybe_modifier(bits, 8, :super)
      |> maybe_modifier(bits, 4, :ctrl)
      |> maybe_modifier(bits, 2, :alt)
      |> maybe_modifier(bits, 1, :shift)
    else
      _ -> []
    end
  end

  defp parse_int(nil), do: nil

  defp parse_int(field) do
    case Integer.parse(field) do
      {value, ""} -> value
      _ -> nil
    end
  end

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
      # Raw mode disables ICRNL, so Enter is CR and a bare LF is Ctrl+J —
      # which applications read as "insert a newline", not "submit".
      "\n" -> {:key, {:char, "j"}, [:ctrl]}
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

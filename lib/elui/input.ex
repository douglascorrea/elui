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

  This plays the role of ratatui's event backends (crossterm events).
  """

  @doc """
  Enables raw mode and starts reading keys, sending events to
  `subscriber`. Returns the reader pid.
  """
  @spec start(pid()) :: pid()
  def start(subscriber \\ self()) do
    enable_raw_mode()
    parser = spawn_link(fn -> parse_loop(subscriber, []) end)
    spawn_link(fn -> read_loop(parser) end)
  end

  @doc "Enables terminal raw mode."
  @spec enable_raw_mode() :: :ok
  def enable_raw_mode do
    # OTP 26+: switch the noshell tty driver to raw mode.
    :shell.start_interactive({:noshell, :raw})
    :ok
  rescue
    _ -> stty(["raw", "-echo"])
  catch
    _, _ -> stty(["raw", "-echo"])
  end

  @doc "Restores the terminal to cooked (normal) mode."
  @spec disable_raw_mode() :: :ok
  def disable_raw_mode do
    :shell.start_interactive({:noshell, :cooked})
    :ok
  rescue
    _ -> stty(["-raw", "echo"])
  catch
    _, _ -> stty(["-raw", "echo"])
  end

  defp stty(args) do
    System.cmd("stty", args, stderr_to_stdout: true)
    :ok
  rescue
    _ -> :ok
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
    if ch =~ ~r/[0-9;]/ do
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

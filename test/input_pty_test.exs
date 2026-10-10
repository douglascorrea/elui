defmodule Elui.InputPtyTest do
  use ExUnit.Case, async: false

  @tag :pty
  test "raw mode lets Ctrl+S reach the application instead of terminal flow control" do
    probe = Path.expand("support/input_pty_probe", __DIR__)
    ebin = Path.expand("../_build/test/lib/elui/ebin", __DIR__)
    elixir = System.find_executable("elixir")

    output = run_in_pty(elixir, ebin, probe)

    assert output =~ "PROBE_EVENT={:key, {:char, \"s\"}, [:ctrl]}"
    assert output =~ "PROBE_RESTORED=true"
    refute output =~ "PROBE_TIMEOUT"
  end

  @tag :pty
  test "real raw-mode input keeps modifiers and tells LF from CR" do
    # These three are indistinguishable without the parser doing its job, and
    # each one is a key a terminal application actually binds: Shift+Enter for
    # "newline, don't submit", Ctrl+J for the same thing without the protocol,
    # and Ctrl+Left for word motion.
    probe = Path.expand("support/input_pty_keys_probe", __DIR__)
    ebin = Path.expand("../_build/test/lib/elui/ebin", __DIR__)
    elixir = System.find_executable("elixir")

    # Octal escapes for the runner; `[` is escaped because expect reads Tcl.
    keys = [
      # Shift+Enter: ESC [ 1 3 ; 2 u
      "\\033\\[13;2u",
      # Ctrl+J
      "\\012",
      # Enter
      "\\015",
      # Ctrl+Left: ESC [ 1 ; 5 D
      "\\033\\[1;5D"
    ]

    output = run_in_pty(elixir, ebin, probe, Enum.join(keys))

    assert output =~ "PROBE_EVENT={:key, :enter, [:shift]}"
    assert output =~ "PROBE_EVENT={:key, {:char, \"j\"}, [:ctrl]}"
    assert output =~ "PROBE_EVENT={:key, :enter, []}"
    assert output =~ "PROBE_EVENT={:key, :left, [:ctrl]}"
    assert output =~ "PROBE_DONE"
  end

  @tag :pty
  test "a mouse report that arrives in two pieces is still one mouse event" do
    # A loaded machine (or a group leader busy writing a frame) can hold back
    # the rest of a sequence for longer than the escape time. Timing out then
    # used to send Escape followed by `[<35;10;5M` as typed text — which
    # interrupts a coding agent and leaves garbage at its prompt.
    probe = Path.expand("support/input_pty_keys_probe", __DIR__)
    ebin = Path.expand("../_build/test/lib/elui/ebin", __DIR__)
    elixir = System.find_executable("elixir")

    output = run_in_pty(elixir, ebin, probe, [{"\\033\\[<35;10", 200}, {";5M", 0}])

    assert output =~ "PROBE_EVENT={:mouse, :move, 9, 4, []}"
    refute output =~ "PROBE_EVENT={:key, :esc, []}"
    refute output =~ ~s(PROBE_EVENT={:key, {:char, ")
    assert output =~ "PROBE_DONE"
  end

  @tag :pty
  test "Escape on its own still arrives after the escape time" do
    probe = Path.expand("support/input_pty_keys_probe", __DIR__)
    ebin = Path.expand("../_build/test/lib/elui/ebin", __DIR__)
    elixir = System.find_executable("elixir")

    output = run_in_pty(elixir, ebin, probe, [{"\\033", 200}, {"a", 0}])

    assert output =~ ~r/PROBE_EVENT={:key, :esc, \[\]}\r?\nPROBE_EVENT={:key, {:char, "a"}, \[\]}/
  end

  # `send_keys` is a string, or `{keys, pause_ms}` pieces sent in order with
  # a pause after each.
  defp run_in_pty(elixir, ebin, probe, send_keys \\ "\\023") do
    command = Enum.join([elixir, "-pa", ebin, probe], " ")
    pieces = if is_binary(send_keys), do: [{send_keys, 0}], else: send_keys

    cond do
      # Prefer expect: it synchronizes on PROBE_READY. The script fallback's
      # timed write can race a cold BEAM startup and be swallowed by IXON.
      expect = System.find_executable("expect") ->
        sends =
          Enum.map_join(pieces, " ", fn {keys, pause} -> "send \"#{keys}\"; after #{pause};" end)

        script =
          "spawn -noecho #{command}; expect PROBE_READY; #{sends} " <>
            "after 1500; send \\021; expect eof"

        {output, 0} = System.cmd(expect, ["-c", script], stderr_to_stdout: true)
        output

      script = System.find_executable("script") ->
        script_command =
          case :os.type() do
            {:unix, :darwin} -> "#{script} -q /dev/null #{command}"
            _other -> "#{script} -q -c '#{command}' /dev/null"
          end

        # `[` has to be escaped for Tcl but not for printf.
        sends =
          Enum.map_join(pieces, " ", fn {keys, pause} ->
            "printf '#{String.replace(keys, "\\[", "[")}'; sleep #{pause / 1000};"
          end)

        quoted = "(sleep 1; #{sends} sleep 2; printf '\\021') | #{script_command}"

        {output, 0} = System.cmd("sh", ["-c", quoted], stderr_to_stdout: true)
        output

      true ->
        flunk("a PTY runner (expect or script) is required")
    end
  end
end

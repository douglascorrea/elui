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

  defp run_in_pty(elixir, ebin, probe, send_keys \\ "\\023") do
    command = Enum.join([elixir, "-pa", ebin, probe], " ")

    cond do
      # Prefer expect: it synchronizes on PROBE_READY. The script fallback's
      # timed write can race a cold BEAM startup and be swallowed by IXON.
      expect = System.find_executable("expect") ->
        script =
          "spawn -noecho #{command}; expect PROBE_READY; send \"#{send_keys}\"; " <>
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
        keys = String.replace(send_keys, "\\[", "[")
        quoted = "(sleep 1; printf '#{keys}'; sleep 2; printf '\\021') | #{script_command}"

        {output, 0} = System.cmd("sh", ["-c", quoted], stderr_to_stdout: true)
        output

      true ->
        flunk("a PTY runner (expect or script) is required")
    end
  end
end

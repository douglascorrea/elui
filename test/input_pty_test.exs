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

  defp run_in_pty(elixir, ebin, probe) do
    command = Enum.join([elixir, "-pa", ebin, probe], " ")

    cond do
      script = System.find_executable("script") ->
        script_command =
          case :os.type() do
            {:unix, :darwin} -> "#{script} -q /dev/null #{command}"
            _other -> "#{script} -q -c '#{command}' /dev/null"
          end

        quoted = "(sleep 1; printf '\\023'; sleep 2; printf '\\021') | #{script_command}"

        {output, 0} = System.cmd("sh", ["-c", quoted], stderr_to_stdout: true)
        output

      expect = System.find_executable("expect") ->
        script =
          "spawn -noecho #{command}; expect PROBE_READY; send \\023; after 1500; send \\021; expect eof"

        {output, 0} = System.cmd(expect, ["-c", script], stderr_to_stdout: true)
        output

      true ->
        flunk("a PTY runner (expect or script) is required")
    end
  end
end

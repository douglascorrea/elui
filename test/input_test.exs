defmodule Elui.InputTest do
  # Pure parsing — no terminal, no raw mode. See input_pty_test.exs for the
  # end-to-end path through a real tty.
  use ExUnit.Case, async: true

  alias Elui.Input

  defp keys(data) do
    {events, ""} = Input.parse(data)
    events
  end

  defp key(data) do
    assert [event] = keys(data)
    event
  end

  describe "control codes" do
    test "CR is Enter and LF is Ctrl+J" do
      # Raw mode disables ICRNL: an application that wants "newline, don't
      # submit" reads Ctrl+J, so LF must not collapse into Enter.
      assert key("\r") == {:key, :enter, []}
      assert key("\n") == {:key, {:char, "j"}, [:ctrl]}
    end

    test "other control codes keep their letter" do
      assert key(<<19>>) == {:key, {:char, "s"}, [:ctrl]}
      assert key("\t") == {:key, :tab, []}
      assert key(<<127>>) == {:key, :backspace, []}
      assert key(<<8>>) == {:key, :backspace, []}
    end

    test "alt is ESC then the key" do
      assert key("\ex") == {:key, {:char, "x"}, [:alt]}
    end
  end

  describe "CSI modifiers" do
    test "unmodified arrows" do
      assert key("\e[A") == {:key, :up, []}
      assert key("\e[D") == {:key, :left, []}
      assert key("\eOP") == {:key, {:f, 1}, []}
    end

    test "modifiers come from the second parameter" do
      assert key("\e[1;5A") == {:key, :up, [:ctrl]}
      assert key("\e[1;2D") == {:key, :left, [:shift]}
      assert key("\e[1;3B") == {:key, :down, [:alt]}
      assert key("\e[1;2H") == {:key, :home, [:shift]}
    end

    test "the modifier field is a 1-based bitmask" do
      assert key("\e[1;9C") == {:key, :right, [:super]}
      assert key("\e[1;8C") == {:key, :right, [:shift, :alt, :ctrl]}
      assert key("\e[1;16C") == {:key, :right, [:shift, :alt, :ctrl, :super]}
      # 1 is "no modifiers", not "shift".
      assert key("\e[1;1C") == {:key, :right, []}
    end

    test "tilde keys carry modifiers too" do
      assert key("\e[3~") == {:key, :delete, []}
      assert key("\e[3;5~") == {:key, :delete, [:ctrl]}
      assert key("\e[5~") == {:key, :page_up, []}
    end

    test "mouse reports still parse" do
      assert key("\e[<0;10;5M") == {:mouse, {:down, :left}, 9, 4, []}
    end
  end

  describe "kitty keyboard protocol" do
    test "Shift+Enter is distinguishable from Enter" do
      # The whole point of the protocol for this codebase: \r cannot carry a
      # modifier, CSI u can.
      assert key("\e[13;2u") == {:key, :enter, [:shift]}
      assert key("\e[13u") == {:key, :enter, []}
    end

    test "legacy codepoints keep their key identity" do
      assert key("\e[27u") == {:key, :esc, []}
      assert key("\e[9;5u") == {:key, :tab, [:ctrl]}
      assert key("\e[127;5u") == {:key, :backspace, [:ctrl]}
      assert key("\e[32;3u") == {:key, :space, [:alt]}
    end

    test "private-use codes map to functional keys" do
      assert key("\e[57352u") == {:key, :up, []}
      assert key("\e[57349;5u") == {:key, :delete, [:ctrl]}
      assert key("\e[57344u") == {:key, :esc, []}
    end

    test "unmapped private-use codes are dropped, not typed" do
      # 57441 is a press of the left shift key itself in report-all mode.
      assert keys("\e[57441u") == []
      assert keys("\e[57441;2ua") == [{:key, {:char, "a"}, []}]
    end

    test "text keys report what was typed, not the base layout key" do
      assert key("\e[97;2u") == {:key, {:char, "a"}, [:shift]}
      # `97;2:1;65u`: base `a`, shift held, text `A`.
      assert key("\e[97;2:1;65u") == {:key, {:char, "A"}, [:shift]}
      # Shifted alternate in the first field, no text field.
      assert key("\e[97:65;2u") == {:key, {:char, "A"}, [:shift]}
    end

    test "key releases are dropped so keys do not double up" do
      assert keys("\e[97;1:3u") == []
      assert keys("\e[97;1:1u") == [{:key, {:char, "a"}, []}]
      assert keys("\e[97;1:2u") == [{:key, {:char, "a"}, []}]
    end
  end

  describe "framing" do
    test "a trailing partial sequence is returned for the next chunk" do
      assert Input.parse("\e[") == {[], "\e["}
      assert Input.parse("a\e[1;") == {[{:key, {:char, "a"}, []}], "\e[1;"}
      assert Input.parse("\e") == {[], "\e"}
    end

    test "a chunk with several events yields them in order" do
      assert keys("\e[Aab\e[13;2u") == [
               {:key, :up, []},
               {:key, {:char, "a"}, []},
               {:key, {:char, "b"}, []},
               {:key, :enter, [:shift]}
             ]
    end
  end
end

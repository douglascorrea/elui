defmodule Elui.StyleTest do
  use ExUnit.Case, async: true

  alias Elui.Style
  alias Elui.Style.Color

  test "patch overrides set values and keeps unset ones" do
    base = Style.new(fg: :red, bg: :black)
    patched = Style.patch(base, Style.new(fg: :blue))
    assert patched.fg == :blue
    assert patched.bg == :black
  end

  test "modifiers accumulate through patch" do
    a = Style.new(add_modifier: [:bold])
    b = Style.new(add_modifier: [:italic])
    patched = Style.patch(a, b)
    assert MapSet.member?(patched.add_modifier, :bold)
    assert MapSet.member?(patched.add_modifier, :italic)
  end

  test "sub_modifier removes previously added modifiers" do
    a = Style.new(add_modifier: [:bold])
    b = Style.new(sub_modifier: [:bold])
    patched = Style.patch(a, b)
    refute MapSet.member?(patched.add_modifier, :bold)
  end

  test "patch gives the same styles as the full set arithmetic" do
    # The formula patch/2 used before its shortcuts for styles without
    # modifiers; every pair must still come out the same.
    reference = fn style, other ->
      %Style{
        fg: other.fg || style.fg,
        bg: other.bg || style.bg,
        underline_color: other.underline_color || style.underline_color,
        add_modifier:
          style.add_modifier
          |> MapSet.difference(other.sub_modifier)
          |> MapSet.union(other.add_modifier),
        sub_modifier:
          style.sub_modifier
          |> MapSet.difference(other.add_modifier)
          |> MapSet.union(other.sub_modifier)
      }
    end

    modifiers = [[], [:bold], [:italic], [:bold, :italic], [:bold, :dim]]

    styles =
      [Style.reset(), Style.new(add_modifier: [:bold], sub_modifier: [:bold])] ++
        for add <- modifiers,
            sub <- modifiers,
            colors <- [[], [fg: :red, bg: {:rgb, 1, 2, 3}], [underline_color: :blue]] do
          Style.new([add_modifier: add, sub_modifier: sub] ++ colors)
        end

    plain? = &(MapSet.size(&1.add_modifier) == 0 and MapSet.size(&1.sub_modifier) == 0)
    pairs = for style <- styles, other <- styles, do: {style, other}

    # Each shortcut and the full path are all exercised.
    assert Enum.any?(pairs, fn {s, o} -> plain?.(s) and plain?.(o) end)
    assert Enum.any?(pairs, fn {s, o} -> not plain?.(s) and plain?.(o) end)
    assert Enum.any?(pairs, fn {s, o} -> plain?.(s) and not plain?.(o) end)
    assert Enum.any?(pairs, fn {s, o} -> not plain?.(s) and not plain?.(o) end)

    for {style, other} <- pairs do
      assert Style.patch(style, other) === reference.(style, other),
             "patch(#{inspect(style)}, #{inspect(other)})"
    end
  end

  test "fluent helpers" do
    style = Style.new() |> Style.fg(:red) |> Style.bold() |> Style.italic()
    assert style.fg == :red
    assert MapSet.member?(style.add_modifier, :bold)
    assert MapSet.member?(style.add_modifier, :italic)
  end

  test "color parsing" do
    assert Color.from_string("red") == {:ok, :red}
    assert Color.from_string("light-blue") == {:ok, :light_blue}
    assert Color.from_string("#ff0000") == {:ok, {:rgb, 255, 0, 0}}
    assert Color.from_string("42") == {:ok, {:indexed, 42}}
    assert Color.from_string("nope") == :error
  end

  test "ansi codes" do
    assert Color.fg_codes(:red) == [31]
    assert Color.bg_codes(:red) == [41]
    assert Color.fg_codes({:rgb, 1, 2, 3}) == [38, 2, 1, 2, 3]
    assert Color.fg_codes({:indexed, 100}) == [38, 5, 100]
  end
end

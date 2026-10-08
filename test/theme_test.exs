defmodule Elui.ThemeTest do
  use ExUnit.Case, async: true

  alias Elui.Theme

  test "built-in names and default" do
    assert Theme.names() == [
             "dark",
             "light",
             "high-contrast",
             "opencode",
             "tokyonight",
             "catppuccin"
           ]

    assert Theme.default_name() == "dark"
    assert Theme.default().name == "dark"
  end

  test "get/1 returns every built-in and rejects unknown names" do
    for name <- Theme.names() do
      assert {:ok, %Theme{name: ^name} = theme} = Theme.get(name)

      for role <- Theme.roles() do
        assert %Elui.Style{} = Theme.style(theme, role)
      end
    end

    assert Theme.get("nope") == :error
  end

  test "opts/2 exposes style fields for widgets" do
    theme = Theme.get!("dark")
    opts = Theme.opts(theme, :highlight)

    assert opts[:fg] == :black
    assert opts[:bg] == :blue
    assert :bold in opts[:add_modifier]
  end

  test "high-contrast emphasizes borders and titles" do
    theme = Theme.get!("high-contrast")
    assert Theme.style(theme, :border).fg == :white
    assert MapSet.member?(Theme.style(theme, :title).add_modifier, :underlined)
  end

  test "colorful themes expose distinct truecolor semantic palettes" do
    assert Theme.style(Theme.get!("opencode"), :accent).fg == {:rgb, 157, 124, 216}
    assert Theme.style(Theme.get!("tokyonight"), :bg).bg == {:rgb, 26, 27, 38}
    assert Theme.style(Theme.get!("catppuccin"), :title).fg == {:rgb, 203, 166, 247}

    assert Enum.uniq(Enum.map(~w(opencode tokyonight catppuccin), &Theme.get!(&1).roles))
           |> length() == 3

    for name <- ~w(opencode tokyonight catppuccin), role <- Theme.roles() do
      style = name |> Theme.get!() |> Theme.style(role)
      colors = [style.fg, style.bg] |> Enum.reject(&is_nil/1)
      assert colors != []
      assert Enum.all?(colors, &match?({:rgb, _, _, _}, &1))
    end
  end
end

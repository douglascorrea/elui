defmodule Elui.ThemeTest do
  use ExUnit.Case, async: true

  alias Elui.Theme

  test "built-in names and default" do
    assert Theme.names() == ["dark", "light", "high-contrast"]
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
end

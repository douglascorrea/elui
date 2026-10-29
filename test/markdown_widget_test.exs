defmodule Elui.Widgets.MarkdownTest do
  use ExUnit.Case, async: true

  alias Elui.Backend.Test, as: TestBackend
  alias Elui.{Buffer, Frame, Style, Terminal, Theme}
  alias Elui.Text.Line
  alias Elui.Widgets.{Block, Markdown}

  # The plain lines at `width`, without trailing spaces.
  defp lines(markdown, width, opts \\ []) do
    markdown
    |> Markdown.new(opts)
    |> Markdown.to_text(width)
    |> Map.fetch!(:lines)
    |> Enum.map(&(&1 |> Line.to_text() |> String.trim_trailing()))
  end

  defp draw(widget, width, height) do
    terminal = Terminal.new(backend: TestBackend, backend_opts: [width: width, height: height])

    {terminal, _} =
      Terminal.draw(terminal, fn frame ->
        Frame.render_widget(frame, widget, Frame.area(frame))
      end)

    Terminal.backend_state(terminal)
  end

  defp cell_style(state, x, y),
    do: state |> TestBackend.buffer() |> Buffer.get(x, y) |> Map.fetch!(:style)

  describe "layout" do
    test "blocks are a blank line apart; headings show their level; rules fill the width" do
      assert lines("# Title\nText *here*.\n\n### Small\n\n---", 12) == [
               "# Title",
               "",
               "Text here.",
               "",
               "### Small",
               "",
               "────────────"
             ]
    end

    test "paragraphs wrap at spaces, keep hard breaks, and cut words wider than the line" do
      assert lines("one two three four  \nfive abcdefghijkl", 9) == [
               "one two",
               "three",
               "four",
               "five",
               "abcdefghi",
               "jkl"
             ]
    end

    test "wide characters wrap by their width" do
      assert lines("日本語のテキスト", 6) == ["日本語", "のテキ", "スト"]
    end

    test "list items hang under their text; bullets change with depth; numbers align" do
      markdown =
        "- first item wraps\n  - nested\n    - deeper\n      - fourth\n- [ ] todo\n- [x] done\n\n9. nine\n10. ten"

      assert lines(markdown, 14) == [
               "• first item",
               "  wraps",
               "  ◦ nested",
               "    ▪ deeper",
               "      • fourth",
               "[ ] todo",
               "[x] done",
               "",
               " 9. nine",
               "10. ten"
             ]
    end

    test "loose lists keep blank lines between items and blocks" do
      assert lines("1. a\n\n   more\n2. b", 10) == ["1. a", "", "   more", "", "2. b"]
    end

    test "quotes keep their bar on every line, nested too" do
      assert lines("> a quote that wraps\n>\n> > nested", 12) == [
               "│ a quote",
               "│ that wraps",
               "│",
               "│ │ nested"
             ]
    end

    test "code blocks are indented and cut at the edge, not wrapped" do
      assert lines("```\nfoo bar baz\n\n  x\n```", 9) == ["  foo bar", "   baz", "", "    x"]
    end

    test "links show their URL unless it is the text, or show_urls is off" do
      markdown = "[docs](https://d.io) <https://e.io> ![logo](l.png)"

      assert lines(markdown, 80) == ["docs (https://d.io) https://e.io [image: logo] (l.png)"]
      assert lines(markdown, 80, show_urls: false) == ["docs https://e.io [image: logo]"]
    end

    test "tables size columns to their cells and align them" do
      markdown =
        "| Name | Qty | Note |\n|:-----|----:|:----:|\n| apple | 3 | ok |\n| kiwi | 12 | |"

      assert lines(markdown, 40) == [
               "Name  │ Qty │ Note",
               "──────┼─────┼─────",
               "apple │   3 │  ok",
               "kiwi  │  12 │"
             ]
    end

    test "a table too wide narrows its widest column and wraps its cells" do
      markdown = "| a | text |\n|---|---|\n| 1 | a long cell that wraps |"

      assert lines(markdown, 16) == [
               "a │ text",
               "──┼─────────────",
               "1 │ a long cell",
               "  │ that wraps"
             ]
    end

    test "mermaid blocks are diagrams; their source when they don't fit or are turned off" do
      markdown = "```mermaid\ngraph LR\n  A --> B\n```"
      diagram = ["  ┌───┐    ┌───┐", "  │ A ├───►│ B │", "  └───┘    └───┘"]
      source = ["  graph LR", "    A --> B"]

      assert lines(markdown, 40) == diagram
      assert lines(markdown, 12) == source
      assert lines(markdown, 40, mermaid: false) == source
      assert lines("```mermaid\nnot a diagram\n```", 40) == ["  not a diagram"]
      assert lines(markdown, 40, mermaid: [ascii: true]) |> hd() == "  +---+    +---+"
    end

    test "nesting deeper than the width still lays out" do
      assert lines("> > > ***\n\n- > ---", 3) == ["│ │ │ ─", "", "• │ ─"]
    end

    test "parsed blocks render the same as the string" do
      markdown = "# Hi\n\n- *a*"
      blocks = Elui.Markdown.parse(markdown)
      assert lines(blocks, 20) == lines(markdown, 20)
    end
  end

  describe "drawing" do
    test "styles headings, emphasis, code, links and markers" do
      state = draw(Markdown.new("## Hi\n\n*a* **b** `c` [d](u)\n\n- e"), 20, 6)

      assert cell_style(state, 0, 0) == Style.new(fg: :dark_gray)
      assert cell_style(state, 3, 0) == Style.new(fg: :cyan, add_modifier: [:bold])
      assert cell_style(state, 0, 2) == Style.new(add_modifier: [:italic])
      assert cell_style(state, 2, 2) == Style.new(add_modifier: [:bold])
      assert cell_style(state, 4, 2) == Style.new(fg: :yellow)
      assert cell_style(state, 6, 2) == Style.new(fg: :blue, add_modifier: [:underlined])
      assert cell_style(state, 8, 2) == Style.new(fg: :dark_gray)
      assert cell_style(state, 0, 4) == Style.new(fg: :dark_gray)
    end

    test "the :styles option and theme_styles/1 replace the defaults" do
      state =
        draw(Markdown.new("# Hi `x`", styles: [heading: [fg: :red], code: [fg: :green]]), 10, 1)

      assert cell_style(state, 2, 0) == Style.new(fg: :red)
      assert cell_style(state, 5, 0) == Style.new(fg: :green)

      theme = Theme.dark()
      state = draw(Markdown.new("# Hi", styles: Markdown.theme_styles(theme)), 10, 1)
      assert cell_style(state, 2, 0) == Theme.style(theme, :title)
    end

    test "draws inside a block, scrolled, over the base style" do
      widget =
        Markdown.new("one\n\ntwo\n\nthree",
          block: Block.bordered(),
          scroll: 2,
          style: [bg: :blue]
        )

      state = draw(widget, 9, 4)

      assert TestBackend.to_lines(state) == ["┌───────┐", "│two    │", "│       │", "└───────┘"]
      assert cell_style(state, 1, 1) == Style.new(bg: :blue)
      assert Markdown.line_count(widget, 7) == 5
    end

    test ":scroll is a number of rows" do
      assert_raise ArgumentError, ~r/:scroll must be a number of rows/, fn ->
        Markdown.new("text", scroll: {1, 0})
      end
    end
  end
end

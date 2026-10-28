defmodule Elui.MarkdownTest do
  use ExUnit.Case, async: true

  import Elui.Markdown, only: [parse: 1]

  defp inlines(markdown) do
    [{:paragraph, inlines}] = parse(markdown)
    inlines
  end

  describe "headings and rules" do
    test "ATX headings drop closing hashes; a # without a space is text" do
      assert parse("# One\n###### Six ##\n#hashtag\n####### seven") == [
               {:heading, 1, [text: "One"]},
               {:heading, 6, [text: "Six"]},
               {:paragraph, [text: "#hashtag ####### seven"]}
             ]
    end

    test "setext headings; --- under a paragraph is a heading, not a rule" do
      assert parse("Big\n===\n\nSmall\n---") == [
               {:heading, 1, [text: "Big"]},
               {:heading, 2, [text: "Small"]}
             ]

      assert parse("***\n- - -\n___") == [:rule, :rule, :rule]
    end
  end

  describe "emphasis" do
    test "*, _, ** and ~~ pair up, and nest" do
      assert inlines("*a* _b_ **c** __d__ ~~e~~ ***f***") == [
               emphasis: [text: "a"],
               text: " ",
               emphasis: [text: "b"],
               text: " ",
               strong: [text: "c"],
               text: " ",
               strong: [text: "d"],
               text: " ",
               strikethrough: [text: "e"],
               text: " ",
               emphasis: [strong: [text: "f"]]
             ]

      assert inlines("**bold *both* bold**") == [
               strong: [text: "bold ", emphasis: [text: "both"], text: " bold"]
             ]

      assert inlines("*foo**bar**baz*") == [
               emphasis: [text: "foo", strong: [text: "bar"], text: "baz"]
             ]
    end

    test "unpaired runs, runs inside words with _, and ~~~ stay text" do
      assert inlines("snake_case_name") == [text: "snake_case_name"]
      assert inlines("2 * 3 * 4") == [text: "2 * 3 * 4"]
      assert inlines("**unclosed and *open") == [text: "**unclosed and *open"]
      assert inlines("a ~~~no~~~") == [text: "a ~~~no~~~"]
    end

    test "thousands of unpaired runs and brackets parse in linear time" do
      text =
        String.duplicate("*a ", 2000) <>
          String.duplicate("a_ ", 2000) <>
          String.duplicate("[", 2000) <> String.duplicate("](", 2000)

      {microseconds, [{:paragraph, _}]} = :timer.tc(fn -> parse(text) end)
      assert microseconds < 2_000_000
    end
  end

  describe "inlines" do
    test "code spans hold formatting characters; an unclosed backtick is text" do
      assert inlines("`*a*` ``b ` c`` ` d ` `open") == [
               code: "*a*",
               text: " ",
               code: "b ` c",
               text: " ",
               code: "d",
               text: " `open"
             ]
    end

    test "escapes, entities and line breaks" do
      assert inlines("\\*not\\* &amp; &copy; &#65; &#x1F600; &bogus;") == [
               text: "*not* & © A 😀 &bogus;"
             ]

      assert inlines("one  \ntwo\\\nthree<br>four\nfive") == [
               {:text, "one"},
               :line_break,
               {:text, "two"},
               :line_break,
               {:text, "three"},
               :line_break,
               {:text, "four five"}
             ]
    end

    test "inline, reference and auto links, and images" do
      markdown = """
      [a](https://a.io "title") [b](<https://b.io/x y>) [c](https://c.io/(p)) ![alt *x*](i.png)
      <https://d.io> <me@e.io> [ref] [Ref][] [text][ref] [missing] [x]

      [ref]: https://ref.io
      """

      assert inlines(markdown) == [
               {:link, [text: "a"], "https://a.io"},
               {:text, " "},
               {:link, [text: "b"], "https://b.io/x y"},
               {:text, " "},
               {:link, [text: "c"], "https://c.io/(p)"},
               {:text, " "},
               {:image, "alt x", "i.png"},
               {:text, " "},
               {:link, [text: "https://d.io"], "https://d.io"},
               {:text, " "},
               {:link, [text: "me@e.io"], "mailto:me@e.io"},
               {:text, " "},
               {:link, [text: "ref"], "https://ref.io"},
               {:text, " "},
               {:link, [text: "Ref"], "https://ref.io"},
               {:text, " "},
               {:link, [text: "text"], "https://ref.io"},
               {:text, " [missing] [x]"}
             ]
    end

    test "links don't nest, but an image can sit in a link and a link in an image" do
      assert inlines("[a [b](c) d](e)") == [
               {:text, "[a "},
               {:link, [text: "b"], "c"},
               {:text, " d](e)"}
             ]

      assert inlines("[![m](i.png)](/u) ![a [b](c)](d)") == [
               {:link, [{:image, "m", "i.png"}], "/u"},
               {:text, " "},
               {:image, "a b", "d"}
             ]

      # A code span binds tighter than a link.
      assert inlines("[foo`](/uri)`") == [text: "[foo", code: "](/uri)"]
    end

    test "a definition needs a destination; only <> gives an empty one" do
      assert parse("[TODO]:\n\nhello [TODO]") == [
               {:paragraph, [text: "[TODO]:"]},
               {:paragraph, [text: "hello [TODO]"]}
             ]

      assert parse("[e]: <>\n\n[e]") == [{:paragraph, [{:link, [text: "e"], ""}]}]
    end

    test "definitions alone make no setext heading; the underline stays" do
      assert parse("[a]: /u\n===") == [{:paragraph, [text: "==="]}]
      assert parse("[a]: /u\n---") == [:rule]
    end

    test "text/1 drops the formatting" do
      assert "**a** `b` [c](u) ![d](i)" |> inlines() |> Elui.Markdown.text() == "a b c d"
    end
  end

  describe "code" do
    test "fenced and indented code keep their lines" do
      markdown =
        "```elixir\nIO.puts(1)\n\n  x\n````\n\n    indented\n\n    more\n\n  ~~~\n   two\n one\n\n~~~ open"

      assert parse(markdown) == [
               {:code_block, "elixir", ["IO.puts(1)", "", "  x"]},
               {:code_block, "", ["indented", "", "more"]},
               {:code_block, "", [" two", "one", "", "~~~ open"]}
             ]
    end
  end

  describe "quotes" do
    test "nest, and take lazy lines into their paragraph" do
      assert parse("> a\nlazy\n>\n> > b\n\nafter") == [
               {:quote, [{:paragraph, [text: "a lazy"]}, {:quote, [{:paragraph, [text: "b"]}]}]},
               {:paragraph, [text: "after"]}
             ]
    end

    test "a lazy line only continues a paragraph; after any other block it leaves the quote" do
      assert parse("> ```\n> code\nfoo") == [
               {:quote, [{:code_block, "", ["code"]}]},
               {:paragraph, [text: "foo"]}
             ]

      assert parse("> # Title\nfoo") == [
               {:quote, [{:heading, 1, [text: "Title"]}]},
               {:paragraph, [text: "foo"]}
             ]

      assert [{:quote, [{:table, _, _, [_]}]}, {:paragraph, [text: "next"]}] =
               parse("> | a | b |\n> |---|---|\n> | 1 | 2 |\nnext")

      assert parse("> > a\n> >\nfoo") == [
               {:quote, [{:quote, [{:paragraph, [text: "a"]}]}]},
               {:paragraph, [text: "foo"]}
             ]

      # Lazy text is never a setext underline.
      assert parse("> a\n===") == [{:quote, [{:paragraph, [text: "a ==="]}]}]
    end
  end

  describe "lists" do
    test "nest by indent, continue lazily, and hold tasks" do
      assert parse("- a\n  - b\n    continued\nlazy\n- [ ] todo\n- [x] done\n- [y] not a task") ==
               [
                 {:list, nil, true,
                  [
                    {:item, nil,
                     [
                       {:paragraph, [text: "a"]},
                       {:list, nil, true,
                        [{:item, nil, [{:paragraph, [text: "b continued lazy"]}]}]}
                     ]},
                    {:item, :todo, [{:paragraph, [text: "todo"]}]},
                    {:item, :done, [{:paragraph, [text: "done"]}]},
                    {:item, nil, [{:paragraph, [text: "[y] not a task"]}]}
                  ]}
               ]
    end

    test "ordered lists keep their start; a blank line between items or blocks loosens a list" do
      assert parse("3. three\n4) four") == [
               {:list, 3, true, [{:item, nil, [{:paragraph, [text: "three"]}]}]},
               {:list, 4, true, [{:item, nil, [{:paragraph, [text: "four"]}]}]}
             ]

      assert [{:list, 1, false, [_, _]}] = parse("1. a\n\n2. b")
      assert [{:list, nil, false, [{:item, nil, [_, _]}]}] = parse("- a\n\n  more of a")

      assert [{:list, nil, true, [{:item, nil, [_, {:code_block, "", _}]}]}] =
               parse("- a\n  ```\n\n  ```")
    end

    test "end at a rule, a different bullet, or an unindented line after a blank" do
      assert [
               {:list, nil, true, [_]},
               :rule,
               {:list, nil, true, [_]},
               {:list, nil, true, [_]},
               {:paragraph, [text: "after"]}
             ] = parse("- a\n***\n- b\n+ c\n\nafter")
    end

    test "a bullet or 1. interrupts a paragraph, another number does not" do
      assert [{:paragraph, [text: "text"]}, {:list, nil, true, _}] = parse("text\n- item")
      assert [{:paragraph, [text: "text"]}, {:list, 1, true, _}] = parse("text\n1. item")
      assert parse("text\n2. not a list") == [{:paragraph, [text: "text 2. not a list"]}]
    end

    test "a line after an item's closing fence is not lazy: it ends the list" do
      assert parse("1. Install:\n   ```sh\n   mix deps.get\n   ```\nThen run it.") == [
               {:list, 1, true,
                [
                  {:item, nil,
                   [{:paragraph, [text: "Install:"]}, {:code_block, "sh", ["mix deps.get"]}]}
                ]},
               {:paragraph, [text: "Then run it."]}
             ]
    end

    test "tabs and CRLF line ends" do
      assert parse("- a\r\n\tb") == [
               {:list, nil, true, [{:item, nil, [{:paragraph, [text: "a b"]}]}]}
             ]
    end
  end

  describe "tables" do
    test "align columns, unescape pipes and fill short rows" do
      markdown = "| a | b | c |\n|:--|:-:|--:|\n| `x\\|y` | **2** |\nnot | a | row\n\nafter"

      assert parse(markdown) == [
               {:table, [:left, :center, :right], [[text: "a"], [text: "b"], [text: "c"]],
                [
                  [[code: "x|y"], [strong: [text: "2"]], []],
                  [[text: "not"], [text: "a"], [text: "row"]]
                ]},
               {:paragraph, [text: "after"]}
             ]
    end

    test "need a delimiter row with a cell for every header cell" do
      assert parse("a | b\n---") == [{:heading, 2, [text: "a | b"]}]
      assert parse("a | b\n--|--|--") == [{:paragraph, [text: "a | b --|--|--"]}]
    end
  end
end

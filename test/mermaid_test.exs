defmodule Elui.MermaidTest do
  use ExUnit.Case, async: true

  alias Elui.Mermaid
  alias Elui.Text.Line

  # The plain lines of a drawing, without trailing spaces.
  defp draw(source, opts \\ []) do
    {:ok, lines} = Mermaid.render(source, opts)
    Enum.map(lines, &(&1 |> Line.to_text() |> String.trim_trailing()))
  end

  defp chart(source) do
    {:ok, {{:flowchart, chart}, _title}} = Mermaid.parse(source)
    chart
  end

  defp sequence(source) do
    {:ok, {{:sequence, diagram}, _title}} = Mermaid.parse(source)
    diagram
  end

  defp edge(chart, from, to), do: Enum.find(chart.edges, &(&1.from == from and &1.to == to))

  defp label(lines), do: Elui.Mermaid.Label.text(lines)

  describe "flowchart parsing" do
    test "reads the direction, `TD` when there is none" do
      assert chart("flowchart LR\n A --> B").direction == :lr
      assert chart("graph BT\n A --> B").direction == :bt
      assert chart("flowchart RL\n A --> B").direction == :rl
      assert chart("graph TB\n A --> B").direction == :tb
      assert chart("flowchart\n A --> B").direction == :tb
      assert chart("graph >\n A --> B").direction == :lr
    end

    test "reads node shapes and labels" do
      chart =
        chart("""
        flowchart TD
          a[rect] --> b(round) --> c([stadium]) --> d[[sub]] --> e[(db)]
          f((circle)) --> g>flag] --> h{rhombus} --> i{{hex}} --> j[/lean/]
          k[\\back\\] --> l[/trap\\] --> m[\\inv/] --> n(((double))) --> o
          p@{ shape: diamond, label: "Decide" }
        """)

      shapes = Map.new(chart.nodes, fn {id, node} -> {id, node.shape} end)

      assert shapes == %{
               "a" => :rect,
               "b" => :round,
               "c" => :stadium,
               "d" => :subroutine,
               "e" => :cylinder,
               "f" => :circle,
               "g" => :asymmetric,
               "h" => :rhombus,
               "i" => :hexagon,
               "j" => :lean_right,
               "k" => :lean_left,
               "l" => :trapezoid,
               "m" => :inv_trapezoid,
               "n" => :double_circle,
               "o" => :rect,
               "p" => :rhombus
             }

      assert label(chart.nodes["c"].label) == "stadium"
      assert label(chart.nodes["o"].label) == "o"
      assert label(chart.nodes["p"].label) == "Decide"
    end

    test "keeps the last label a node was given, in source order" do
      chart = chart("graph TD\n A --> B[Bee]\n C --> A[Ay]")
      assert chart.order == ["A", "B", "C"]
      assert label(chart.nodes["A"].label) == "Ay"
    end

    test "reads link lines, ends, lengths and labels" do
      chart =
        chart("""
        flowchart LR
          a --> b
          b --- c
          c -.-> d
          d ==> e
          e --o f
          f --x g
          g <--> h
          h ~~~ i
          i ---> j
          j -- text --> k
          k -->|piped| l
          l -. dots .-> m
          m == thick ==> n
          n -..-> o
          o ====> p
        """)

      assert %{line: :solid, head: :arrow, tail: nil, length: 1} = edge(chart, "a", "b")
      assert %{line: :solid, head: nil, length: 1} = edge(chart, "b", "c")
      assert %{line: :dotted, head: :arrow} = edge(chart, "c", "d")
      assert %{line: :thick, head: :arrow} = edge(chart, "d", "e")
      assert %{head: :circle} = edge(chart, "e", "f")
      assert %{head: :cross} = edge(chart, "f", "g")
      assert %{head: :arrow, tail: :arrow} = edge(chart, "g", "h")
      assert %{line: :invisible} = edge(chart, "h", "i")
      assert %{length: 2} = edge(chart, "i", "j")
      assert label(edge(chart, "j", "k").label) == "text"
      assert label(edge(chart, "k", "l").label) == "piped"
      assert %{line: :dotted} = edge(chart, "l", "m")
      assert label(edge(chart, "l", "m").label) == "dots"
      assert %{line: :thick} = edge(chart, "m", "n")
      assert label(edge(chart, "m", "n").label) == "thick"
      assert %{line: :dotted, length: 2} = edge(chart, "n", "o")
      assert %{line: :thick, length: 3} = edge(chart, "o", "p")
    end

    test "reads chains and `&` groups" do
      chart = chart("graph TD\n A & B --> C & D --> E")

      assert Enum.map(chart.edges, &{&1.from, &1.to}) == [
               {"A", "C"},
               {"A", "D"},
               {"B", "C"},
               {"B", "D"},
               {"C", "E"},
               {"D", "E"}
             ]
    end

    test "reads one-liners, comments and statements it doesn't draw" do
      chart =
        chart("""
        graph TD; A-->B; B-->C
        %% a comment
        classDef red fill:#f00;
        class A red
        style B fill:#bbf,stroke:#f66
        click C "https://example.com" "Tooltip"
        linkStyle 0 stroke:#ff3
        A:::red --> D
        """)

      assert chart.order == ["A", "B", "C", "D"]
      assert length(chart.edges) == 3
    end

    test "puts nodes in the subgraph that mentions them, as Mermaid does" do
      chart =
        chart("""
        flowchart TB
          c1 --> a2
          subgraph one [First]
            a1 --> a2
          end
          subgraph two
            subgraph inner
              b1
            end
            b2
          end
        """)

      assert chart.parents == %{
               "a1" => "one",
               "a2" => "one",
               "b1" => "inner",
               "inner" => "two",
               "b2" => "two"
             }

      assert label(chart.subgraphs["one"].title) == "First"
      assert label(chart.subgraphs["two"].title) == "two"
    end

    test "keeps a node named like its subgraph, and never nests a subgraph in itself" do
      chart = chart("graph TD\n subgraph db [Database]\n db[(Postgres)]\n end\n app --> db")
      assert chart.nodes["db"].shape == :cylinder
      assert [{renamed, %{title: title}}] = Map.to_list(chart.subgraphs)
      assert chart.parents == %{"db" => renamed}
      assert label(title) == "Database"
      assert [%{from: "app", to: "db"}] = chart.edges

      for source <- [
            "graph TD\n subgraph S\n subgraph S\n x\n end\n end",
            "graph TD\n subgraph S\n x --> S\n end",
            "graph TD\n subgraph A\n B\n end\n subgraph B\n A\n end"
          ] do
        parents = chart(source).parents
        refute Enum.any?(parents, fn {id, parent} -> id == parent end)
        assert {:ok, _lines} = Mermaid.render(source)
      end
    end

    test "draws an empty subgraph as a node" do
      chart = chart("graph TD\n subgraph empty [Nothing here]\n end\n A --> empty")
      assert label(chart.nodes["empty"].label) == "Nothing here"
      assert chart.subgraphs == %{}
    end

    test "decodes entity codes, `<br>`, tags and markdown strings in labels" do
      chart =
        chart("""
        graph TD
          A["say #quot;hi#quot; &amp; #9829;"]
          B["one<br>two<br/>three"]
          C["`**bold** and *it*`"]
          D["<b>strong</b> text"]
        """)

      assert label(chart.nodes["A"].label) == "say \"hi\" & ♥"

      assert label(chart("graph TD\n A[\"#infin; &ne; &bogus;\"]").nodes["A"].label) ==
               "∞ ≠ &bogus;"

      assert length(chart.nodes["B"].label) == 3

      [[bold, plain, italic]] = chart.nodes["C"].label
      assert {bold.content, :bold in bold.style.add_modifier} == {"bold", true}
      assert plain.content == " and "
      assert {italic.content, :italic in italic.style.add_modifier} == {"it", true}

      [[strong, _rest]] = chart.nodes["D"].label
      assert :bold in strong.style.add_modifier
    end

    test "reports what it can't read, with the line" do
      assert Mermaid.parse("graph TD\n  A --> B\n  C -->") ==
               {:error, "line 3: expected a node after a link"}

      assert Mermaid.parse("graph TD\n  A --> B\n  end") ==
               {:error, "line 3: `end` without a `subgraph`"}

      assert {:error, "line 2: unclosed" <> _} = Mermaid.parse("graph TD\n  A[open --> B")
      assert {:error, "line 2: unexpected" <> _} = Mermaid.parse("graph TD\n  A B")
      assert Mermaid.parse("") == {:error, "no diagram"}
      assert Mermaid.parse("pie\n \"a\": 1") == {:error, "\"pie\" diagrams are not supported"}
      assert Mermaid.parse(<<"graph TD\n ", 255>>) == {:error, "the source is not UTF-8"}
    end

    test "skips `%%{…}%%` directives over several lines" do
      assert {:ok, _diagram} =
               Mermaid.parse("%%{\n  init: { \"theme\": \"dark\" }\n}%%\ngraph TD\n A --> B")

      assert Mermaid.parse("%%{\n init: {}\n}%%\ngraph TD\n A -->") ==
               {:error, "line 5: expected a node after a link"}
    end

    test "reads a title from front matter" do
      assert {:ok, {{:flowchart, _chart}, "Flow"}} =
               Mermaid.parse("---\ntitle: Flow\n---\ngraph TD\n A --> B")
    end
  end

  describe "flowchart drawing" do
    test "draws nodes and an edge top down" do
      assert draw("graph TD\n  A --> B") == [
               "┌───┐",
               "│ A │",
               "└─┬─┘",
               "  │",
               "  ▼",
               "┌───┐",
               "│ B │",
               "└───┘"
             ]
    end

    test "lines a decision's branches up with their nodes" do
      assert draw("""
             flowchart TD
               A[Start] --> B{Is it?}
               B -->|Yes| C[OK]
               B -->|No| D[Not OK]
               C --> E[End]
               D --> E
             """) == [
               "     ┌───────┐",
               "     │ Start │",
               "     └───┬───┘",
               "         │",
               "         ▼",
               "    ╱─────────╲",
               "    │ Is it?  │",
               "    ╲────┬────╱",
               "   ╭─────┴─────╮",
               "   │           │",
               "  Yes          No",
               "   │           │",
               "   ▼           ▼",
               "┌─────┐   ┌─────────┐",
               "│ OK  │   │ Not OK  │",
               "└──┬──┘   └────┬────┘",
               "   │           │",
               "   ╰─────┬─────╯",
               "         ▼",
               "      ┌─────┐",
               "      │ End │",
               "      └─────┘"
             ]
    end

    test "draws left to right and right to left with labels on the line" do
      assert draw("flowchart LR\n  A -- text --> B -- more --> C") == [
               "┌───┐         ┌───┐         ┌───┐",
               "│ A ├─ text ─►│ B ├─ more ─►│ C │",
               "└───┘         └───┘         └───┘"
             ]

      assert draw("flowchart RL\n  A -- text --> B") == [
               "┌───┐         ┌───┐",
               "│ B │◄─ text ─┤ A │",
               "└───┘         └───┘"
             ]
    end

    test "draws bottom to top" do
      assert draw("flowchart BT\n  A --> B") == [
               "┌───┐",
               "│ B │",
               "└───┘",
               "  ▲",
               "  │",
               "┌─┴─┐",
               "│ A │",
               "└───┘"
             ]
    end

    test "draws a link back up beside the one going down" do
      assert draw("graph TD\n  A --> B --> A") == [
               "┌─────┐",
               "│  A  │",
               "└──┬──┘",
               "   │ ▲",
               "   │ │",
               "   ▼ │",
               "┌────┴┐",
               "│  B  │",
               "└─────┘"
             ]
    end

    test "gives each kind of end its own port" do
      assert draw("flowchart TD\n  A --> C\n  B --x C") == [
               "┌───┐   ┌───┐",
               "│ A │   │ B │",
               "└─┬─┘   └─┬─┘",
               "  │       │",
               "  ╰──╮ ╭──╯",
               "     ▼ ×",
               "  ┌─────┐",
               "  │  C  │",
               "  └─────┘"
             ]
    end

    test "turns an edge twice where two edges would swap columns" do
      for direction <- ~w(TD LR RL BT) do
        source = "flowchart #{direction}\n  A --> D & E\n  B --> D & F\n  C --> E & F\n  A --> F"
        assert apart?(source), "edges share a line in #{direction}"
      end
    end

    test "draws a loop from a node to itself, with its label" do
      assert draw("graph TD\n  A -->|retry| A\n  A --> B") == [
               "┌───┐",
               "│ A ├─╮ retry",
               "│   │◄╯",
               "└─┬─┘",
               "  │",
               "  ▼",
               "┌───┐",
               "│ B │",
               "└───┘"
             ]

      assert draw("flowchart LR\n  A -->|retry| A\n  A --> B\n  A ~~~ A") == [
               "┌─────┐    ┌───┐",
               "│  A  ├───►│ B │",
               "└┬────┘    └───┘",
               " │▲",
               " ╰╯",
               " retry"
             ]

      assert draw("flowchart RL\n  A -->|retry| A\n  A --> B") == [
               "┌───┐    ┌─────┐",
               "│ B │◄───┤  A  │",
               "└───┘    └────┬┘",
               "             ▲│",
               "             ╰╯",
               "          retry"
             ]
    end

    test "refuses a drawing too large, quickly" do
      tall = Enum.map_join(1..3000, "<br>", fn _ -> "x" end)
      wide = Enum.map_join(1..150, " & ", &"A#{&1}")
      flowchart = "flowchart TD\n  T[\"#{tall}\"] --> #{wide}"

      sequence =
        "sequenceDiagram\n" <>
          Enum.map_join(1..200, "\n", &"  P#{rem(&1, 200) + 1}->>P#{rem(&1 * 7, 200) + 1}: m")

      assert Mermaid.render(flowchart) == {:error, "the diagram is too large to draw"}
      assert Mermaid.render(sequence) == {:error, "the diagram is too large to draw"}
    end

    test "draws a subgraph around its nodes, its title clear of edges" do
      assert draw("flowchart TB\n  subgraph one [Group]\n    a --> b\n  end\n  c --> a") == [
               "  ┌───┐",
               "  │ c │",
               "  └─┬─┘",
               "    │",
               "╭───│ Group ─╮",
               "│   ▼        │",
               "│ ┌───┐      │",
               "│ │ a │      │",
               "│ └─┬─┘      │",
               "│   │        │",
               "│   ▼        │",
               "│ ┌───┐      │",
               "│ │ b │      │",
               "│ └───┘      │",
               "╰────────────╯"
             ]
    end

    test "draws shapes, meeting edges in their middle row" do
      assert draw("graph LR\n  A([stadium]) --> B[(db)] --> C{if} --> D[[sub]]") == [
               "               ╭────╮",
               "╭─────────╮    ├────┤    ╱────╲    ┌┬─────┬┐",
               "( stadium ├───►│ db ├───►│ if ├───►││ sub ││",
               "╰─────────╯    │    │    ╲────╱    └┴─────┴┘",
               "               ╰────╯"
             ]
    end

    test "draws each kind of link" do
      assert draw("graph LR\n  A -.-> B ==> C --x D --o E <--> F --- G ~~~ H") == [
               "┌───┐    ┌───┐    ┌───┐    ┌───┐    ┌───┐     ┌───┐   ┌───┐   ┌───┐",
               "│ A ├┄┄┄►│ B ┣━━━►│ C ├───×│ D ├───○│ E │◄───►│ F ├───┤ G │   │ H │",
               "└───┘    └───┘    └───┘    └───┘    └───┘     └───┘   └───┘   └───┘"
             ]
    end

    test "draws in ASCII" do
      assert draw("graph TD\n  A{x} -->|y| B", ascii: true) == [
               "/---\\",
               "| x |",
               "\\-+-/",
               "  |",
               "  y",
               "  |",
               "  v",
               "+---+",
               "| B |",
               "+---+"
             ]
    end

    test "wraps labels narrower to fit a width" do
      source = "graph LR\n  A[a label long enough to wrap] --> B[another long label here]"
      wide = draw(source)
      narrow = draw(source, width: 40)

      assert Enum.max(Enum.map(wide, &String.length/1)) > 40
      assert Enum.max(Enum.map(narrow, &String.length/1)) <= 40
      assert length(narrow) > length(wide)
    end

    test "puts the front matter title above the diagram" do
      assert ["Flow", "", "┌───┐" | _] = draw("---\ntitle: Flow\n---\ngraph TD\n A --> B")
    end

    test "styles each part by its role" do
      {:ok, [top, middle | _]} =
        Mermaid.render("graph LR\n A --> B", styles: [node: [fg: :red], label: [fg: :green]])

      assert hd(top.spans).style.fg == :red
      assert Enum.find(middle.spans, &(&1.content =~ "A")).style.fg == :green
    end

    test "lays out what it is given without crossing nodes or boxes" do
      :rand.seed(:exsss, {1, 2, 3})

      for _ <- 1..40 do
        ids = for i <- 1..8, do: "n#{i}"
        links = ["-->", "-.->", "==>", "<-->", "---", "-->|x|", "--->"]

        edges =
          for _ <- 1..10,
              do: "  #{Enum.random(ids)} #{Enum.random(links)} #{Enum.random(ids)}"

        groups = [
          "  subgraph g1\n    #{Enum.random(ids)}\n    #{Enum.random(ids)}\n  end",
          "  subgraph g2\n    #{Enum.random(ids)}\n  end"
        ]

        direction = Enum.random(~w(TD LR BT RL))
        source = "flowchart #{direction}\n" <> Enum.join(edges ++ groups, "\n")
        geometry = Elui.Mermaid.Layout.run(chart(source))

        boxes = Enum.map(geometry.nodes, &{&1.x, &1.y, &1.w, &1.h})

        for {a, i} <- Enum.with_index(boxes), {b, j} <- Enum.with_index(boxes), i < j do
          refute overlap?(a, b), "nodes overlap in:\n#{source}"
        end

        assert apart?(source), "edges share a line in:\n#{source}"
        assert {:ok, _lines} = Mermaid.render(source)
      end
    end
  end

  # Whether edges that share no end run along each other anywhere.
  defp apart?(source) do
    runs =
      source
      |> chart()
      |> Elui.Mermaid.Layout.run()
      |> Map.fetch!(:edges)
      |> Enum.reject(&(&1.edge.line == :invisible))
      |> Enum.map(fn %{points: points} ->
        cells = Elui.Mermaid.Grid.cells(points)

        along =
          [cells, [nil | cells], Enum.drop(cells, 1) ++ [nil]]
          |> Enum.zip()
          |> Enum.flat_map(fn {cell, before, next} ->
            for other <- [before, next], other, do: {cell, axis(cell, other)}
          end)
          |> MapSet.new()

        {hd(cells), List.last(cells), along}
      end)

    for {{s1, e1, a1}, i} <- Enum.with_index(runs),
        {{s2, e2, a2}, j} <- Enum.with_index(runs),
        i < j,
        s1 != s2 and e1 != e2,
        reduce: true do
      apart -> apart and MapSet.disjoint?(a1, a2)
    end
  end

  defp axis({x, _y1}, {x, _y2}), do: :vertical
  defp axis(_cell, _other), do: :horizontal

  defp overlap?({x1, y1, w1, h1}, {x2, y2, w2, h2}),
    do: x1 < x2 + w2 and x2 < x1 + w1 and y1 < y2 + h2 and y2 < y1 + h1

  describe "sequence diagrams" do
    test "reads participants, messages and notes" do
      diagram =
        sequence("""
        sequenceDiagram
          participant A as Alice
          actor B
          A->>+B: hello
          B-->>-A: hi
          A-xB: lost
          A-)B: async
          A<<->>B: both
          Note over A,B: shared
          C->>A: new
        """)

      assert Enum.map(diagram.participants, &{&1.id, &1.kind, label(&1.label)}) == [
               {"A", :participant, "Alice"},
               {"B", :actor, "B"},
               {"C", :participant, "C"}
             ]

      messages = for {:message, message} <- diagram.events, do: message

      assert Enum.map(messages, &{&1.line, &1.head, &1.tail}) == [
               {:solid, :arrow, nil},
               {:dotted, :arrow, nil},
               {:solid, :cross, nil},
               {:solid, :arrow, nil},
               {:solid, :arrow, :arrow},
               {:solid, :arrow, nil}
             ]

      assert [%{activate: true}, %{deactivate: true} | _] = messages

      assert {:note, :over, ["A", "B"], _text} =
               Enum.find(diagram.events, &match?({:note, _, _, _}, &1))
    end

    test "draws messages between lifelines, their text above them" do
      assert draw("sequenceDiagram\n  Alice->>John: Hello John\n  John-->>Alice: Hi") == [
               "┌───────┐     ┌───────┐",
               "│ Alice │     │ John  │",
               "└───┬───┘     └───┬───┘",
               "    │ Hello John  │",
               "    ├────────────►│",
               "    │     Hi      │",
               "    │◄┄┄┄┄┄┄┄┄┄┄┄┄┤",
               "    │             │",
               "┌───┴───┐     ┌───┴───┐",
               "│ Alice │     │ John  │",
               "└───────┘     └───────┘"
             ]
    end

    test "draws numbers, self messages, notes, activations and blocks" do
      assert draw("""
             sequenceDiagram
               autonumber
               participant C as Client
               actor S as Server
               C->>+S: ask
               S->>S: think
               Note right of S: busy
               alt ok
                 S-->>-C: answer
               else failed
                 S--xC: error
               end
             """) == [
               "┌─────────┐  ╭─────────╮",
               "│ Client  │  │ Server  │",
               "└────┬────┘  ╰────┬────╯",
               "     │  1. ask    │",
               "     ├───────────►┃",
               "     │            ┣──╮ 2. think",
               "     │            ┃◄─╯",
               "     │            ┃ ┌──────┐",
               "     │            ┃ │ busy │",
               "     │            ┃ └──────┘",
               "   ┌─ alt [ok] ─────┐",
               "   │ │ 3. answer  ┃ │",
               "   │ │◄┄┄┄┄┄┄┄┄┄┄┄┫ │",
               "   ├┄ [failed] ┄┄┄┄┄┤",
               "   │ │ 4. error   │ │",
               "   │ │×┄┄┄┄┄┄┄┄┄┄┄┤ │",
               "   └────────────────┘",
               "     │            │",
               "┌────┴────┐  ╭────┴────╮",
               "│ Client  │  │ Server  │",
               "└─────────┘  ╰─────────╯"
             ]
    end

    test "frames a note left of the first participant whole" do
      assert draw("""
             sequenceDiagram
               loop Daily
                 Note left of Alice: hi there
               end
               Alice->>Bob: hi
             """) == [
               "           ┌───────┐  ┌─────┐",
               "           │ Alice │  │ Bob │",
               "           └───┬───┘  └──┬──┘",
               "┌─ loop [Daily] ─┐       │",
               "│ ┌──────────┐ │ │       │",
               "│ │ hi there │ │ │       │",
               "│ └──────────┘ │ │       │",
               "└────────────────┘       │",
               "               │   hi    │",
               "               ├────────►│",
               "               │         │",
               "           ┌───┴───┐  ┌──┴──┐",
               "           │ Alice │  │ Bob │",
               "           └───────┘  └─────┘"
             ]
    end

    test "reads `;` as a line break, numbers from a start by a step, and leaves out empty labels" do
      assert draw("""
             sequenceDiagram
               autonumber 10 5
               A->>B: x; B->>A: y
               alt ok
                 A->>B: z
               else
                 B->>A: w
               end
               rect rgb(0,0,0)
                 A->>B: v
               end
             """) == [
               "┌───┐    ┌───┐",
               "│ A │    │ B │",
               "└─┬─┘    └─┬─┘",
               "  │ 10. x  │",
               "  ├───────►│",
               "  │ 15. y  │",
               "  │◄───────┤",
               "┌─ alt [ok] ─┐",
               "│ │ 20. z  │ │",
               "│ ├───────►│ │",
               "├┄┄┄┄┄┄┄┄┄┄┄┄┤",
               "│ │ 25. w  │ │",
               "│ │◄───────┤ │",
               "└────────────┘",
               "┌────────────┐",
               "│ │ 30. v  │ │",
               "│ ├───────►│ │",
               "└────────────┘",
               "  │        │",
               "┌─┴─┐    ┌─┴─┐",
               "│ A │    │ B │",
               "└───┘    └───┘"
             ]
    end

    test "takes a title from the diagram" do
      assert ["Hello", "" | _] = draw("sequenceDiagram\n  title Hello\n  A->>B: hi")
    end

    test "reports what it can't read" do
      assert Mermaid.parse("sequenceDiagram\n  A->>B: hi\n  end") ==
               {:error, "line 3: `end` without a block"}

      assert Mermaid.parse("sequenceDiagram\n  what is this") ==
               {:error, "line 2: can't read \"what is this\""}
    end

    test "closes blocks left open" do
      assert {:ok, _lines} = Mermaid.render("sequenceDiagram\n  loop forever\n  A->>B: hi")
    end
  end

  test "render!/2 raises on source it can't read" do
    assert_raise ArgumentError, "Mermaid: no diagram", fn -> Mermaid.render!("") end
  end
end

Code.require_file("support/ratatui_port.exs", __DIR__)

# Mermaid viewer: draws Mermaid diagrams with Elui.Widgets.Mermaid, a few
# samples or the files given, laid out at the window's width.
#
# Run with:
#
#     mix run examples/mermaid.exs [FILE...]

defmodule Examples.Mermaid do
  @behaviour Elui.App

  alias Elui.{Frame, Layout}
  alias Elui.Widgets.{Block, Mermaid}

  @samples [
    {"Decision",
     """
     flowchart TD
       A[Start] --> B{Is it working?}
       B -->|Yes| C[Ship it]
       B -->|No| D[Debug]
       D --> E[Fix the bug]
       E --> B
       C --> F([Done])
     """},
    {"Services",
     """
     flowchart LR
       subgraph Client
         UI[Web UI] --> SDK[SDK]
       end
       subgraph Backend
         API[API] --> Orders[Orders]
         Orders --> DB[(Postgres)]
       end
       SDK -->|REST| API
       Orders -.->|events| Bus{{Event bus}}
     """},
    {"Checkout",
     """
     sequenceDiagram
       autonumber
       actor U as User
       participant W as Web
       participant P as Payments
       U->>W: Pay
       W->>+P: Charge card
       alt approved
         P-->>W: OK
       else declined
         P--xW: Declined
       end
       deactivate P
       W-->>U: Receipt
       Note over U,W: done
     """}
  ]

  @impl true
  def init(_opts) do
    diagrams =
      case System.argv() do
        [] -> @samples
        paths -> Enum.map(paths, &{Path.basename(&1), File.read!(&1)})
      end

    %{diagrams: diagrams, index: 0, ascii: false, scroll: {0, 0}}
  end

  @impl true
  def update(model, event) do
    cond do
      Examples.Support.quit?(event) -> :quit
      Examples.Support.key?(event, [:tab, :right]) or char?(event, "n") -> {:ok, step(model, 1)}
      Examples.Support.key?(event, [:back_tab, :left]) or char?(event, "p") -> {:ok, step(model, -1)}
      Examples.Support.key?(event, :down) or char?(event, "j") -> {:ok, scroll(model, 1, 0)}
      Examples.Support.key?(event, :up) or char?(event, "k") -> {:ok, scroll(model, -1, 0)}
      char?(event, "l") -> {:ok, scroll(model, 0, 4)}
      char?(event, "h") -> {:ok, scroll(model, 0, -4)}
      char?(event, "a") -> {:ok, %{model | ascii: not model.ascii}}
      true -> {:ok, model}
    end
  end

  @impl true
  def view(model, frame) do
    [header, body, footer] =
      Layout.vertical([{:length, 1}, {:fill, 1}, {:length, 1}])
      |> Layout.split(Frame.area(frame))

    {title, source} = Enum.at(model.diagrams, model.index)
    count = length(model.diagrams)

    frame =
      Examples.Support.render_header(frame, header, "Mermaid", "#{title} (#{model.index + 1}/#{count})")

    widget =
      Mermaid.new(source,
        block: Block.bordered(border_style: [fg: :dark_gray]),
        scroll: model.scroll,
        ascii: model.ascii
      )

    frame = Frame.render_widget(frame, widget, body)

    Examples.Support.render_footer(
      frame,
      footer,
      "Tab/←→ next  ↑/↓ j/k h/l scroll  a #{if model.ascii, do: "box", else: "ASCII"}  q quit"
    )
  end

  defp char?({:key, {:char, char}, _mods}, char), do: true
  defp char?(_event, _char), do: false

  defp step(model, delta) do
    index = Examples.Support.cycle(model.index, delta, length(model.diagrams))
    %{model | index: index, scroll: {0, 0}}
  end

  defp scroll(%{scroll: {rows, columns}} = model, down, right),
    do: %{model | scroll: {max(rows + down, 0), max(columns + right, 0)}}
end

Examples.Support.run(Examples.Mermaid)

defmodule Elui.Mermaid.Layout do
  @moduledoc false

  # Lays a flowchart out on a grid of character cells, in layers, the way
  # dagre does for Mermaid in a browser (Sugiyama's method):
  #
  #   1. rank: each node gets a layer, edges pointing down; edges that
  #      close a cycle are turned around for the layout. Ranks are doubled
  #      so every edge passes an odd rank between its nodes, where its
  #      label goes.
  #   2. normalize: an edge spanning several ranks becomes a chain through
  #      one dummy item per rank.
  #   3. order: items in each layer are sorted by the mean position of
  #      their neighbours, sweeping down and up, keeping the order with
  #      the fewest crossings; a subgraph's items stay together.
  #   4. place: across the layers, items move towards their neighbours
  #      (least squares, then medians on whole cells, which straightens
  #      edges), kept apart by their sizes; subgraph boxes push out what
  #      they overlap.
  #   5. route: between two layers an edge that changes column turns on a
  #      track of its own, tracks sorted so lines don't run over each
  #      other; edges leaving one port share a track, as do edges into
  #      one port.
  #
  # The work is done top to bottom ("rank" is the row, "cross" the
  # column) and turned at the end for `LR`, `RL` and `BT`. Coordinates
  # are `{cross, rank}` until then and `{x, y}` after.

  alias Elui.Mermaid.{Flowchart, Label}
  alias Elui.Text.Span

  @sweeps 24

  @doc """
  Places `chart` and returns its geometry: `%{width, height, nodes,
  edges, labels, clusters, loops}`, every position in cells.
  """
  @spec run(Flowchart.t(), Keyword.t()) :: map()
  def run(%Flowchart{} = chart, opts \\ []) do
    vertical = chart.direction in [:tb, :bt]

    config = %{
      direction: chart.direction,
      vertical: vertical,
      max_label: Keyword.get(opts, :max_label_width, 30),
      node_gap: if(vertical, do: 3, else: 1),
      odd_rank: if(vertical, do: 1, else: 3),
      cluster_cross: if(vertical, do: 2, else: 1),
      cluster_rank: if(vertical, do: 0, else: 1)
    }

    graph = graph(chart, config)

    graph
    |> rank()
    |> clusters(chart)
    |> normalize(config)
    |> order()
    |> ports(config)
    |> place(config)
    |> route(config)
    |> geometry(config)
  end

  # -- the graph ----------------------------------------------------------------------------

  defp graph(chart, config) do
    descendants = descendants(chart)

    edges =
      chart.edges
      |> Enum.map(fn edge ->
        %{
          edge
          | from: anchor(edge.from, descendants, :last),
            to: anchor(edge.to, descendants, :first)
        }
      end)
      |> Enum.filter(&(Map.has_key?(chart.nodes, &1.from) and Map.has_key?(chart.nodes, &1.to)))

    {loops, edges} = Enum.split_with(edges, &(&1.from == &1.to))
    loops = loops |> Enum.reject(&(&1.line == :invisible)) |> Enum.group_by(& &1.from)

    nodes =
      Map.new(chart.order, fn id ->
        node = chart.nodes[id]
        {id, node_item(node, Map.get(loops, id, []), config)}
      end)

    %{
      chart: chart,
      ids: chart.order,
      nodes: nodes,
      edges: edges |> Enum.with_index() |> Enum.map(fn {edge, i} -> Map.put(edge, :index, i) end)
    }
  end

  # The nodes inside each subgraph, nested ones included, in source order.
  defp descendants(chart) do
    Enum.reduce(Enum.reverse(chart.order), %{}, fn id, acc ->
      id
      |> ancestors(chart.parents)
      |> Enum.reduce(acc, fn cluster, acc -> Map.update(acc, cluster, [id], &[id | &1]) end)
    end)
  end

  defp ancestors(id, parents, seen \\ []) do
    case Map.get(parents, id) do
      nil ->
        []

      parent ->
        if parent in seen, do: [], else: [parent | ancestors(parent, parents, [id | seen])]
    end
  end

  # An edge to a subgraph goes to its first node; one from it leaves its last.
  defp anchor(id, descendants, which) do
    case Map.get(descendants, id) do
      nil -> id
      nodes when which == :first -> List.first(nodes)
      nodes -> List.last(nodes)
    end
  end

  defp node_item(node, loops, config) do
    lines = node.label |> Label.wrap(config.max_label) |> nonempty()
    text_width = Label.width(lines)

    {w, h} =
      case node.shape do
        shape when shape in [:circle, :double_circle, :subroutine] ->
          {text_width + 6, length(lines) + 2}

        :cylinder ->
          {text_width + 4, length(lines) + 3}

        _ ->
          {text_width + 4, length(lines) + 2}
      end

    loop_label =
      loops
      |> Enum.map(& &1.label)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&Label.text/1)
      |> case do
        [] -> nil
        texts -> [[texts |> Enum.join(", ") |> Span.raw()]]
      end

    w = max(w, 5)
    # Sideways the loop's label runs under the box, from its second column.
    w = if loop_label && not config.vertical, do: max(w, Label.width(loop_label) + 2), else: w
    w = if config.vertical and rem(w, 2) == 0, do: w + 1, else: w
    # Sideways, edges meet a cylinder in its middle row, below the lid.
    h = if not config.vertical and node.shape == :cylinder and rem(h, 2) == 0, do: h + 1, else: h
    # A loop drawn on the side needs two rows of it.
    h = if loops != [] and config.vertical, do: max(h, 4), else: h

    %{
      kind: :node,
      node: node,
      lines: lines,
      w: w,
      h: h,
      loops: loops,
      loop_label: loop_label
    }
    |> sizes(config)
  end

  defp nonempty([]), do: [[]]
  defp nonempty(lines), do: lines

  # An item's extent along the ranks and on either side of its centre
  # across them: a node's box, plus a loop beside it.
  defp sizes(item, config) do
    {along, across} = if config.vertical, do: {item.h, item.w}, else: {item.w, item.h}
    lo = div(across - 1, 2)
    hi = across - 1 - lo

    extra =
      cond do
        item.loops == [] -> 0
        is_nil(item.loop_label) -> 2
        config.vertical -> 3 + Label.width(item.loop_label)
        true -> 3
      end

    Map.merge(item, %{size: along, lo: lo, hi: hi + extra, box_hi: hi})
  end

  # -- 1. rank ------------------------------------------------------------------------------

  defp rank(graph) do
    back = back_edges(graph.ids, graph.edges)

    edges =
      Enum.map(graph.edges, fn edge ->
        reversed = MapSet.member?(back, edge.index)
        {upper, lower} = if reversed, do: {edge.to, edge.from}, else: {edge.from, edge.to}

        Map.merge(edge, %{upper: upper, lower: lower, reversed: reversed, minlen: 2 * edge.length})
      end)

    outs = Enum.group_by(edges, & &1.upper)
    ins = Enum.group_by(edges, & &1.lower)
    topo = topological(graph.ids, outs, ins)

    ranks =
      Enum.reduce(topo, %{}, fn id, ranks ->
        rank =
          ins
          |> Map.get(id, [])
          |> Enum.map(&(ranks[&1.upper] + &1.minlen))
          |> Enum.max(fn -> 0 end)

        Map.put(ranks, id, rank)
      end)

    # Longest-path ranks put every source at the top; a node with more
    # edges out than in moves down to its successors, shortening them.
    ranks =
      topo
      |> Enum.reverse()
      |> Enum.reduce(ranks, fn id, ranks ->
        out = Map.get(outs, id, [])
        into = Map.get(ins, id, [])

        if out != [] and length(into) < length(out) do
          lowest = out |> Enum.map(&(ranks[&1.lower] - &1.minlen)) |> Enum.min()
          Map.put(ranks, id, max(ranks[id], lowest))
        else
          ranks
        end
      end)

    least = ranks |> Map.values() |> Enum.min(fn -> 0 end)
    ranks = Map.new(ranks, fn {id, rank} -> {id, rank - least} end)

    %{graph | edges: edges} |> Map.put(:ranks, ranks)
  end

  # Edges that close a cycle, found depth first in source order.
  defp back_edges(ids, edges) do
    succ = Enum.group_by(edges, & &1.from, &{&1.to, &1.index})

    {_state, back} =
      Enum.reduce(ids, {%{}, MapSet.new()}, fn id, acc -> visit(id, succ, acc) end)

    back
  end

  defp visit(id, succ, {state, back}) do
    if Map.has_key?(state, id) do
      {state, back}
    else
      {state, back} =
        succ
        |> Map.get(id, [])
        |> Enum.reduce({Map.put(state, id, :open), back}, fn {to, index}, {state, back} ->
          if Map.get(state, to) == :open,
            do: {state, MapSet.put(back, index)},
            else: visit(to, succ, {state, back})
        end)

      {Map.put(state, id, :done), back}
    end
  end

  # Kahn's order, ties broken by source order.
  defp topological(ids, outs, ins) do
    indegree = Map.new(ids, fn id -> {id, length(Map.get(ins, id, []))} end)
    position = ids |> Enum.with_index() |> Map.new()

    ready =
      ids
      |> Enum.filter(&(indegree[&1] == 0))
      |> Enum.map(&{position[&1], &1})
      |> :gb_sets.from_list()

    kahn(ready, indegree, outs, position, [])
  end

  defp kahn(ready, indegree, outs, position, acc) do
    if :gb_sets.is_empty(ready) do
      Enum.reverse(acc)
    else
      {{_position, id}, ready} = :gb_sets.take_smallest(ready)

      {ready, indegree} =
        outs
        |> Map.get(id, [])
        |> Enum.reduce({ready, indegree}, fn edge, {ready, indegree} ->
          indegree = Map.update!(indegree, edge.lower, &(&1 - 1))

          if indegree[edge.lower] == 0,
            do: {:gb_sets.add({position[edge.lower], edge.lower}, ready), indegree},
            else: {ready, indegree}
        end)

      kahn(ready, indegree, outs, position, [id | acc])
    end
  end

  # -- subgraphs ----------------------------------------------------------------------------

  defp clusters(graph, chart) do
    parents = chart.parents

    spans =
      Enum.reduce(graph.ids, %{}, fn id, spans ->
        rank = graph.ranks[id]

        id
        |> ancestors(parents)
        |> Enum.reduce(spans, fn cluster, spans ->
          Map.update(spans, cluster, {rank, rank}, fn {low, high} ->
            {min(low, rank), max(high, rank)}
          end)
        end)
      end)

    clusters =
      Map.new(spans, fn {id, {low, high}} ->
        subgraph = chart.subgraphs[id]
        path = id |> ancestors(parents) |> Enum.reverse()
        title = (subgraph && subgraph.title) || []
        {id, %{id: id, title: title, low: low, high: high, path: path ++ [id]}}
      end)

    Map.put(graph, :clusters, clusters)
  end

  # The subgraphs holding a node, outermost first.
  defp node_path(graph, id) do
    id
    |> ancestors(graph.chart.parents)
    |> Enum.reverse()
    |> Enum.filter(&Map.has_key?(graph.clusters, &1))
  end

  # -- 2. normalize -------------------------------------------------------------------------

  defp normalize(graph, config) do
    items =
      Map.new(graph.ids, fn id ->
        item =
          Map.merge(graph.nodes[id], %{
            id: {:node, id},
            rank: graph.ranks[id],
            path: node_path(graph, id)
          })

        {{:node, id}, item}
      end)

    {items, chains} =
      Enum.reduce(graph.edges, {items, %{}}, fn edge, {items, chains} ->
        top = graph.ranks[edge.upper]
        bottom = graph.ranks[edge.lower]
        label_rank = if edge.label, do: top + 1 + 2 * div(div(bottom - top, 2) - 1, 2)

        {items, middle} =
          Enum.reduce((top + 1)..(bottom - 1)//1, {items, []}, fn rank, {items, middle} ->
            id = {:dummy, edge.index, rank}
            path = dummy_path(graph, edge, rank)

            item =
              if rank == label_rank,
                do: label_item(edge.label, config),
                else: %{kind: :dummy, size: 1, lo: 0, hi: 0, box_hi: 0}

            {Map.put(items, id, Map.merge(item, %{id: id, rank: rank, path: path})),
             [id | middle]}
          end)

        chain = [{:node, edge.upper} | Enum.reverse(middle)] ++ [{:node, edge.lower}]
        {items, Map.put(chains, edge.index, chain)}
      end)

    layers =
      items
      |> Map.values()
      |> Enum.group_by(& &1.rank, & &1.id)

    Map.merge(graph, %{items: items, chains: chains, layers: layers})
  end

  defp label_item(label, config) do
    lines = label |> Label.wrap(config.max_label) |> nonempty()
    width = Label.width(lines)

    {along, across} =
      if config.vertical, do: {length(lines) + 2, width + 2}, else: {width + 4, length(lines)}

    lo = div(across - 1, 2)

    %{
      kind: :label,
      lines: lines,
      size: along,
      lo: lo,
      hi: across - 1 - lo,
      box_hi: across - 1 - lo
    }
  end

  # The subgraph a dummy belongs to: while leaving its upper node's
  # subgraphs it stays in them, then it enters its lower node's; between
  # them it is in the subgraph holding both.
  defp dummy_path(graph, edge, rank) do
    upper =
      edge.upper
      |> ancestors(graph.chart.parents)
      |> Enum.filter(&Map.has_key?(graph.clusters, &1))

    lower =
      edge.lower
      |> ancestors(graph.chart.parents)
      |> Enum.filter(&Map.has_key?(graph.clusters, &1))

    common = Enum.filter(upper, &(&1 in lower))

    cluster =
      Enum.find(upper -- common, &(rank <= graph.clusters[&1].high)) ||
        Enum.find(lower -- common, &(rank >= graph.clusters[&1].low)) ||
        List.first(common)

    if cluster, do: graph.clusters[cluster].path, else: []
  end

  # -- 3. order -----------------------------------------------------------------------------

  defp order(graph) do
    {ups, downs} = neighbours(graph)
    graph = Map.merge(graph, %{ups: ups, downs: downs})
    depth = graph.layers |> Map.keys() |> Enum.max(fn -> 0 end)

    layers = graph |> initial_order(depth) |> regroup(graph)
    best = {crossings(layers, downs, depth), layers}

    {_crossings, layers} =
      Enum.reduce_while(1..@sweeps, {best, layers, 0}, fn sweep, {best, layers, stale} ->
        layers = sweep(graph, layers, depth, rem(sweep, 2) == 1)
        count = crossings(layers, downs, depth)
        {best_count, _best_layers} = best

        cond do
          count < best_count -> {:cont, {{count, layers}, layers, 0}}
          stale >= 4 or best_count == 0 -> {:halt, {best, layers, stale}}
          true -> {:cont, {best, layers, stale + 1}}
        end
      end)
      |> case do
        {best, _layers, _stale} -> best
      end

    layers = regroup(layers, graph)
    Map.merge(graph, %{layers: layers, depth: depth, cluster_rank: cluster_order(graph, layers)})
  end

  # Each subgraph's items together in every layer, and sibling subgraphs
  # in one order in all of them: a sweep leaves its first layer as it
  # was, so this settles the order the boxes are placed by.
  defp regroup(layers, graph) do
    if map_size(graph.clusters) == 0 do
      layers
    else
      cluster_rank = cluster_order(graph, layers)

      Map.new(layers, fn {rank, layer} ->
        entries =
          layer |> Enum.with_index() |> Enum.map(fn {id, i} -> {id, i, graph.items[id].path} end)

        {rank, group_sort(entries, 0, cluster_rank)}
      end)
    end
  end

  # For each item, its neighbours in the layer above and below, weighted
  # to keep chains of dummies straight (dagre's 1, 2, 8). A node can line
  # up with one edge on a side, so its pull is shared among them: an
  # edge leaving a fork turns at the fork, not again further down.
  defp neighbours(graph) do
    links =
      Enum.flat_map(graph.chains, fn {_index, chain} ->
        Enum.chunk_every(chain, 2, 1, :discard)
      end)

    outs = Enum.frequencies_by(links, &hd/1)
    ins = Enum.frequencies_by(links, &List.last/1)

    pairs =
      Enum.map(links, fn [a, b] ->
        weight =
          case {graph.items[a].kind == :node, graph.items[b].kind == :node} do
            {true, true} -> 1
            {false, false} -> 8
            {true, false} -> 2 / outs[a]
            {false, true} -> 2 / ins[b]
          end

        {a, b, weight}
      end)

    {Enum.group_by(pairs, &elem(&1, 1), &{elem(&1, 0), elem(&1, 2)}),
     Enum.group_by(pairs, &elem(&1, 0), &{elem(&1, 1), elem(&1, 2)})}
  end

  # Depth first from the nodes in source order, as dagre starts.
  defp initial_order(graph, depth) do
    starts =
      graph.ids
      |> Enum.with_index()
      |> Enum.sort_by(fn {id, index} -> {graph.ranks[id], index} end)
      |> Enum.map(fn {id, _index} -> {:node, id} end)

    {_seen, layers} =
      Enum.reduce(starts, {MapSet.new(), %{}}, fn id, acc -> place_first(id, graph, acc) end)

    Map.new(0..depth//1, fn rank -> {rank, layers |> Map.get(rank, []) |> Enum.reverse()} end)
  end

  defp place_first(id, graph, {seen, layers}) do
    if MapSet.member?(seen, id) do
      {seen, layers}
    else
      rank = graph.items[id].rank
      acc = {MapSet.put(seen, id), Map.update(layers, rank, [id], &[id | &1])}

      graph.downs
      |> Map.get(id, [])
      |> Enum.reduce(acc, fn {next, _weight}, acc -> place_first(next, graph, acc) end)
    end
  end

  defp sweep(graph, layers, depth, down) do
    ranks = if down, do: 1..depth//1, else: (depth - 1)..0//-1
    neighbours = if down, do: graph.ups, else: graph.downs
    cluster_rank = cluster_order(graph, layers)

    Enum.reduce(ranks, layers, fn rank, layers ->
      reference = if down, do: layers[rank - 1], else: layers[rank + 1]
      positions = reference |> Enum.with_index() |> Map.new()
      Map.put(layers, rank, sort_layer(graph, layers[rank], neighbours, positions, cluster_rank))
    end)
  end

  defp sort_layer(_graph, [], _neighbours, _positions, _cluster_rank), do: []

  defp sort_layer(graph, layer, neighbours, positions, cluster_rank) do
    scale = max(map_size(positions), 1) / max(length(layer), 1)

    layer
    |> Enum.with_index()
    |> Enum.map(fn {id, index} ->
      key =
        case Map.get(neighbours, id, []) do
          [] ->
            index * scale

          list ->
            {sum, total} =
              Enum.reduce(list, {0, 0}, fn {other, weight}, {sum, total} ->
                {sum + weight * Map.get(positions, other, 0), total + weight}
              end)

            sum / total
        end

      {id, key, graph.items[id].path}
    end)
    |> group_sort(0, cluster_rank)
  end

  # Sorts by key, a subgraph's items kept together and sorted among
  # themselves; sibling subgraphs keep the order they have in every layer.
  defp group_sort(entries, depth, cluster_rank) do
    units =
      entries
      |> Enum.group_by(fn {_id, _key, path} -> Enum.at(path, depth) end)
      |> Enum.flat_map(fn
        {nil, direct} ->
          Enum.map(direct, fn {id, key, _path} -> {key, nil, [id]} end)

        {cluster, members} ->
          key = members |> Enum.map(&elem(&1, 1)) |> mean()
          [{key, cluster, group_sort(members, depth + 1, cluster_rank)}]
      end)
      |> Enum.sort_by(fn {key, _cluster, ids} -> {key, ids} end)

    slots = units |> Enum.filter(fn {_key, cluster, _ids} -> cluster end)

    ordered =
      Enum.sort_by(slots, fn {key, cluster, _ids} ->
        {Map.get(cluster_rank, cluster, key), cluster}
      end)

    {units, _ordered} =
      Enum.map_reduce(units, ordered, fn
        {_key, nil, _ids} = unit, ordered -> {unit, ordered}
        _unit, [next | ordered] -> {next, ordered}
      end)

    Enum.flat_map(units, fn {_key, _cluster, ids} -> ids end)
  end

  # Where each subgraph sits, on average over its layers, so siblings
  # come in one order everywhere.
  defp cluster_order(graph, layers) do
    if map_size(graph.clusters) == 0 do
      %{}
    else
      layers
      |> Enum.flat_map(fn {_rank, layer} ->
        count = max(length(layer) - 1, 1)

        layer
        |> Enum.with_index()
        |> Enum.flat_map(fn {id, index} ->
          Enum.map(graph.items[id].path, &{&1, index / count})
        end)
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Map.new(fn {cluster, positions} -> {cluster, mean(positions)} end)
    end
  end

  defp mean(list), do: Enum.sum(list) / length(list)

  defp crossings(layers, downs, depth) do
    Enum.reduce(0..(depth - 1)//1, 0, fn rank, total ->
      lower = layers[rank + 1] |> Enum.with_index() |> Map.new()

      ends =
        layers[rank]
        |> Enum.flat_map(fn id ->
          downs
          |> Map.get(id, [])
          |> Enum.map(fn {other, _weight} -> lower[other] end)
          |> Enum.sort()
        end)

      total + inversions(ends)
    end)
  end

  # Pairs out of order, by merge sort.
  defp inversions(list), do: list |> count_sort() |> elem(1)

  defp count_sort(list) when length(list) < 2, do: {list, 0}

  defp count_sort(list) do
    {left, right} = Enum.split(list, div(length(list), 2))
    {left, a} = count_sort(left)
    {right, b} = count_sort(right)
    {merged, c} = merge(left, length(left), right, [], 0)
    {merged, a + b + c}
  end

  defp merge([], _n, right, acc, count), do: {Enum.reverse(acc, right), count}
  defp merge(left, _n, [], acc, count), do: {Enum.reverse(acc, left), count}

  defp merge([l | left] = all, n, [r | right], acc, count) do
    if r < l,
      do: merge(all, n, right, [r | acc], count + n),
      else: merge(left, n - 1, [r | right], [l | acc], count)
  end

  # -- ports --------------------------------------------------------------------------------

  # Where each edge meets a node, from the middle of the side. A side
  # where edges end in different marks (an arrowhead, a cross, a circle,
  # none) gets a port for each, so no mark sits on another edge's line;
  # such a node needs room for them, and each port beyond the middle one
  # is on the side its edges go.
  defp ports(graph, config) do
    ends =
      Enum.flat_map(graph.edges, fn edge ->
        chain = graph.chains[edge.index]
        forward = not edge.reversed

        [
          %{
            side: {hd(chain), :down},
            index: edge.index,
            next: Enum.at(chain, 1),
            mark: upper_mark(edge),
            forward: forward
          },
          %{
            side: {List.last(chain), :up},
            index: edge.index,
            next: Enum.at(chain, -2),
            mark: lower_mark(edge),
            forward: forward
          }
        ]
      end)

    split =
      ends
      |> Enum.group_by(& &1.side)
      |> Enum.map(fn {side, list} -> {side, Enum.group_by(list, & &1.mark)} end)
      |> Enum.filter(fn {_side, marks} -> map_size(marks) > 1 end)

    # Room for a port each: two either side of the middle across a box
    # seven wide; sideways, one either side in five rows, two in seven.
    items =
      Enum.reduce(split, graph.items, fn {{id, _side}, marks}, items ->
        Map.update!(items, id, fn item ->
          tall = if map_size(marks) > 3, do: 7, else: 5

          cond do
            config.vertical and item.w < 7 -> sizes(%{item | w: 7}, config)
            not config.vertical and item.h < tall -> sizes(%{item | h: tall}, config)
            true -> item
          end
        end)
      end)

    position =
      Enum.reduce(graph.layers, %{}, fn {_rank, layer}, acc ->
        layer |> Enum.with_index() |> Enum.into(acc)
      end)

    shifts =
      Map.new(split, fn {{id, _side} = side, marks} ->
        room = min(items[id].lo, items[id].box_hi) - 1
        {side, mark_offsets(marks, position, room |> min(2) |> max(0))}
      end)

    offsets =
      Map.new(ends, fn end_ ->
        offset = shifts |> Map.get(end_.side, %{}) |> Map.get(end_.mark, 0)
        {{end_.index, elem(end_.side, 1)}, offset}
      end)

    # How far one end of a link wants the other moved: their ports in line.
    pull =
      Enum.reduce(graph.chains, %{}, fn {index, chain}, pull ->
        last = length(chain) - 1

        chain
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.with_index()
        |> Enum.reduce(pull, fn {[a, b], i}, pull ->
          off_a = if i == 0, do: offsets[{index, :down}], else: 0
          off_b = if i + 1 == last, do: offsets[{index, :up}], else: 0
          pull |> Map.put({a, b}, off_b - off_a) |> Map.put({b, a}, off_a - off_b)
        end)
      end)

    Map.merge(graph, %{items: items, offsets: offsets, pull: pull})
  end

  # Each mark's port on a split side. The middle goes to the mark with
  # the most edges going forward (arrowheads, then none, on a tie); the
  # others go to the side their edges lead, as far out as is free, or to
  # the other side when that one is full.
  defp mark_offsets(marks, position, room) do
    preference = %{arrow: 0, nil: 1, cross: 2, circle: 3}

    [{middle, centre} | others] =
      Enum.sort_by(marks, fn {mark, list} ->
        {-Enum.count(list, & &1.forward), preference[mark]}
      end)

    {offsets, _free} =
      others
      |> Enum.sort_by(fn {mark, list} -> {mean_index(list, position), preference[mark]} end)
      |> Enum.reduce({%{middle => 0}, Enum.reject(-room..room//1, &(&1 == 0))}, fn {mark, list},
                                                                                   {offsets, free} ->
        wanted = if mean_index(list, position) >= mean_index(centre, position), do: 1, else: -1

        offset =
          Enum.max_by(free, &{&1 * wanted > 0, abs(&1)}, fn -> 0 end)

        {Map.put(offsets, mark, offset), List.delete(free, offset)}
      end)

    offsets
  end

  defp mean_index(ends, position), do: ends |> Enum.map(&position[&1.next]) |> mean()

  # -- 4. place -----------------------------------------------------------------------------

  defp place(graph, config) do
    graph = Map.put(graph, :crossing, title_crossings(graph, config))
    ranks = 0..graph.depth//1
    sep = fn a, b -> separation(graph.items[a], graph.items[b], config) end

    positions =
      Enum.reduce(ranks, %{}, fn rank, positions ->
        {positions, _last} =
          Enum.reduce(graph.layers[rank], {positions, nil}, fn id, {positions, last} ->
            at = if last, do: positions[last] + sep.(last, id), else: graph.items[id].lo
            {Map.put(positions, id, at), id}
          end)

        positions
      end)

    # Least squares, sweeping down and up.
    positions =
      Enum.reduce(1..4, positions, fn _round, positions ->
        positions
        |> settle_sweep(graph, Enum.drop(ranks, 1), [graph.ups], sep)
        |> settle_sweep(graph, ranks |> Enum.reverse() |> Enum.drop(1), [graph.downs], sep)
      end)
      |> settle_sweep(graph, ranks, [graph.ups, graph.downs], sep)

    positions =
      Enum.reduce(ranks, positions, fn rank, positions ->
        round_layer(positions, graph.layers[rank], sep)
      end)

    # Medians on whole cells line edges up exactly.
    index =
      Enum.reduce(graph.layers, %{}, fn {_rank, layer}, index ->
        layer
        |> Enum.with_index()
        |> Enum.reduce(index, fn {id, i}, index -> Map.put(index, id, i) end)
      end)

    positions =
      Enum.reduce(1..6, positions, fn _round, positions -> align(graph, positions, index, sep) end)

    positions = push_clusters(graph, positions, config)
    Map.put(graph, :positions, normalize_positions(graph, positions, config))
  end

  defp separation(a, b, config) do
    gap = if a.kind == :node and b.kind == :node, do: config.node_gap, else: 1
    boundaries = length(a.path -- b.path) + length(b.path -- a.path)
    a.hi + b.lo + 1 + gap + boundaries * config.cluster_cross
  end

  defp settle_sweep(positions, graph, ranks, sides, sep) do
    Enum.reduce(ranks, positions, fn rank, positions ->
      layer = graph.layers[rank]

      {targets, weights} =
        layer
        |> Enum.map(fn id ->
          list = Enum.flat_map(sides, &Map.get(&1, id, []))

          case list do
            [] ->
              {positions[id], 0.01}

            list ->
              total = list |> Enum.map(&elem(&1, 1)) |> Enum.sum()

              sum =
                list
                |> Enum.map(fn {other, weight} ->
                  weight * (positions[other] + graph.pull[{id, other}])
                end)
                |> Enum.sum()

              {sum / total, total}
          end
        end)
        |> Enum.unzip()

      offsets = offsets(layer, sep)
      values = pav(Enum.zip_with(targets, offsets, &(&1 - &2)), weights)

      layer
      |> Enum.zip(Enum.zip_with(values, offsets, &(&1 + &2)))
      |> Enum.into(positions)
    end)
  end

  defp offsets(layer, sep) do
    layer
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.scan(0, fn [a, b], offset -> offset + sep.(a, b) end)
    |> then(&[0 | &1])
  end

  # Weighted isotonic regression (pool adjacent violators): the closest
  # non-decreasing values.
  defp pav(values, weights) do
    values
    |> Enum.zip(weights)
    |> Enum.reduce([], fn {value, weight}, stack ->
      pool([{value * weight, weight, 1} | stack])
    end)
    |> Enum.reverse()
    |> Enum.flat_map(fn {sum, weight, count} -> List.duplicate(sum / weight, count) end)
  end

  defp pool([{s1, w1, n1}, {s2, w2, n2} | rest]) when s2 / w2 > s1 / w1,
    do: pool([{s1 + s2, w1 + w2, n1 + n2} | rest])

  defp pool(stack), do: stack

  defp round_layer(positions, layer, sep) do
    {positions, _last} =
      Enum.reduce(layer, {positions, nil}, fn id, {positions, last} ->
        at = round(positions[id])
        at = if last, do: max(at, positions[last] + sep.(last, id)), else: at
        {Map.put(positions, id, at), id}
      end)

    positions
  end

  # Items already in line with a neighbour move together, as one block,
  # to the median of where their other neighbours want them, as far as
  # the items beside them allow. A lone item is a block of one.
  defp align(graph, positions, index, sep) do
    graph
    |> blocks(positions)
    |> Enum.reduce(positions, fn block, positions ->
      inside = MapSet.new(block)

      wanted =
        Enum.flat_map(block, fn id ->
          (Map.get(graph.ups, id, []) ++ Map.get(graph.downs, id, []))
          |> Enum.reject(fn {other, _weight} -> MapSet.member?(inside, other) end)
          |> Enum.map(fn {other, weight} ->
            {positions[other] + graph.pull[{id, other}] - positions[id], weight}
          end)
        end)

      if wanted == [] do
        positions
      else
        {low, high} =
          Enum.reduce(block, {:none, :none}, fn id, {low, high} ->
            layer = graph.layers[graph.items[id].rank]
            i = index[id]
            before = if i > 0, do: Enum.at(layer, i - 1)
            next = Enum.at(layer, i + 1)

            low =
              if before,
                do: bound(low, positions[before] + sep.(before, id) - positions[id], &max/2),
                else: low

            high =
              if next,
                do: bound(high, positions[next] - sep.(id, next) - positions[id], &min/2),
                else: high

            {low, high}
          end)

        delta = wanted |> median() |> clamp(low, high)

        if delta == 0,
          do: positions,
          else: Enum.reduce(block, positions, &Map.update!(&2, &1, fn at -> at + delta end))
      end
    end)
  end

  defp bound(:none, value, _pick), do: value
  defp bound(current, value, pick), do: pick.(current, value)

  defp clamp(_target, low, high) when low != :none and high != :none and low > high, do: 0
  defp clamp(target, low, high), do: target |> clamp_low(low) |> clamp_high(high)
  defp clamp_low(target, :none), do: target
  defp clamp_low(target, low), do: max(target, low)
  defp clamp_high(target, :none), do: target
  defp clamp_high(target, high), do: min(target, high)

  # Chains of items in line with each other, top first.
  defp blocks(graph, positions) do
    below =
      graph.downs
      |> Enum.flat_map(fn {id, list} ->
        list
        |> Enum.filter(fn {other, _weight} ->
          positions[other] + graph.pull[{id, other}] == positions[id]
        end)
        |> Enum.map(&{id, elem(&1, 0)})
      end)
      |> Map.new()

    above = Map.new(below, fn {id, other} -> {other, id} end)

    graph.layers
    |> Enum.sort()
    |> Enum.flat_map(fn {_rank, layer} -> layer end)
    |> Enum.reject(&Map.has_key?(above, &1))
    |> Enum.map(fn id -> Stream.iterate(id, &below[&1]) |> Enum.take_while(& &1) end)
  end

  # The weighted median; halfway between the two middle values when the
  # weight splits evenly.
  defp median(list) do
    list = Enum.sort(list)
    half = (list |> Enum.map(&elem(&1, 1)) |> Enum.sum()) / 2

    {result, _sum} =
      list
      |> Enum.with_index()
      |> Enum.reduce_while({nil, 0}, fn {{position, weight}, index}, {_result, sum} ->
        sum = sum + weight

        cond do
          sum > half -> {:halt, {position, sum}}
          sum == half -> {:halt, {div(position + elem(Enum.at(list, index + 1), 0), 2), sum}}
          true -> {:cont, {nil, sum}}
        end
      end)

    result
  end

  # A subgraph's box spans all its layers, so an item of another layer
  # may fall inside it; such items move right, or the box does.
  defp push_clusters(graph, positions, config) do
    if map_size(graph.clusters) == 0 do
      positions
    else
      # Pushes only move right and settle well within this; if they
      # didn't, the boxes are left overlapping rather than pushed apart
      # without end.
      room =
        graph.items
        |> Map.values()
        |> Enum.map(&(&1.lo + &1.hi + 1 + config.node_gap))
        |> Enum.sum()
        |> Kernel.+(4 * config.cluster_cross * map_size(graph.clusters))

      limit = 2 * (room + Enum.max(Map.values(positions), fn -> 0 end))
      pushed = push(graph, positions, config, 200)
      if Enum.any?(pushed, fn {_id, at} -> at > limit end), do: positions, else: pushed
    end
  end

  defp push(_graph, positions, _config, 0), do: positions

  defp push(graph, positions, config, budget) do
    extents = cluster_extents(graph, positions, config)

    case overlap(graph, positions, extents) do
      nil ->
        positions

      {:item, rank, id, delta} ->
        push(graph, shift_from(graph, positions, rank, id, delta), config, budget - 1)

      {:cluster, cluster, delta} ->
        push(graph, shift_cluster(graph, positions, cluster, delta), config, budget - 1)
    end
  end

  # Each subgraph's left and right, around its items and the subgraphs
  # inside it (innermost first), with room for its title.
  defp cluster_extents(graph, positions, config) do
    direct = graph.items |> Map.values() |> Enum.group_by(&List.last(&1.path))

    graph.clusters
    |> Map.values()
    |> Enum.sort_by(&(-length(&1.path)))
    |> Enum.reduce(%{}, fn cluster, extents ->
      items =
        direct
        |> Map.get(cluster.id, [])
        |> Enum.map(&{positions[&1.id] - &1.lo, positions[&1.id] + &1.hi})

      children =
        for {id, child} <- graph.clusters, Enum.at(child.path, -2) == cluster.id, do: extents[id]

      {left, right} =
        (items ++ children)
        |> Enum.reduce(fn {l, r}, {left, right} -> {min(l, left), max(r, right)} end)

      left = left - config.cluster_cross
      right = right + config.cluster_cross

      right =
        if config.vertical,
          do: max(right, title_end(graph, positions, cluster, left)),
          else: right

      Map.put(extents, cluster.id, {left, right})
    end)
  end

  # Up and down the page the title sits in the box's top border; the
  # links that cross that border, as {edge, item inside}.
  defp title_crossings(graph, config) do
    if config.vertical do
      Enum.flat_map(graph.chains, fn {index, chain} ->
        chain
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.flat_map(fn [a, b] ->
          {outside, inside} = if config.direction == :bt, do: {b, a}, else: {a, b}
          top = if config.direction == :bt, do: :high, else: :low

          graph.items[inside].path
          |> Enum.reject(&(&1 in graph.items[outside].path))
          |> Enum.filter(&(Map.fetch!(graph.clusters[&1], top) == graph.items[inside].rank))
          |> Enum.map(&{&1, {index, inside}})
        end)
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    else
      %{}
    end
  end

  # Where a box must reach right for its title (" title ", from two cells
  # in) to clear the edges crossing its top border.
  defp title_end(graph, positions, cluster, left) do
    width = Label.width(cluster.title) + 2

    crossings =
      graph.crossing
      |> Map.get(cluster.id, [])
      |> Enum.map(fn {index, id} ->
        side = if graph.chains[index] |> hd() == id, do: :down, else: :up

        positions[id] +
          if(graph.items[id].kind == :node, do: graph.offsets[{index, side}], else: 0)
      end)

    start =
      Stream.iterate(left + 2, &(&1 + 1))
      |> Enum.find(fn x -> not Enum.any?(crossings, &(&1 >= x and &1 < x + width)) end)

    start + width + 1
  end

  defp overlap(graph, positions, extents) do
    item_overlap(graph, positions, extents) || cluster_overlap(graph, extents)
  end

  defp item_overlap(graph, positions, extents) do
    Enum.find_value(graph.clusters, fn {id, cluster} ->
      {left, right} = extents[id]

      Enum.find_value(cluster.low..cluster.high//1, fn rank ->
        layer = graph.layers[rank] || []
        first = Enum.find_index(layer, &(id in graph.items[&1].path))

        layer
        |> Enum.with_index()
        |> Enum.find_value(fn {other, index} ->
          item = graph.items[other]
          l = positions[other] - item.lo
          r = positions[other] + item.hi

          cond do
            id in item.path or r + 1 < left or l - 1 > right ->
              nil

            # An item of a subgraph beside this one moves with its box.
            is_boolean(before?(graph, item.path, id)) ->
              nil

            (first && index > first) || (is_nil(first) and positions[other] * 2 > left + right) ->
              {:item, rank, other, right + 2 - l}

            true ->
              {:cluster, id, r + 2 - left}
          end
        end)
      end)
    end)
  end

  defp cluster_overlap(graph, extents) do
    pairs =
      for {a, ca} <- graph.clusters,
          {b, cb} <- graph.clusters,
          a < b,
          a not in cb.path and b not in ca.path,
          ca.low <= cb.high and cb.low <= ca.high,
          do: {a, b}

    Enum.find_value(pairs, fn {a, b} ->
      {la, ra} = extents[a]
      {lb, rb} = extents[b]

      if ra + 1 < lb or rb + 1 < la do
        nil
      else
        {first, second} = if before?(graph, graph.clusters[a].path, b), do: {a, b}, else: {b, a}
        {_l1, r1} = extents[first]
        {l2, _r2} = extents[second]
        {:cluster, second, r1 + 2 - l2}
      end
    end)
  end

  # Whether what `path` leads to comes before subgraph `id`, by the order
  # the layers were sorted in, at the depth their paths part; `nil` when
  # `path` ends there, an item beside the subgraph rather than in one.
  defp before?(graph, path, id) do
    theirs = graph.clusters[id].path
    depth = path |> Enum.zip(theirs) |> Enum.take_while(fn {a, b} -> a == b end) |> length()

    case Enum.at(path, depth) do
      nil ->
        nil

      mine ->
        other = Enum.at(theirs, depth)
        {graph.cluster_rank[mine], mine} < {graph.cluster_rank[other], other}
    end
  end

  defp shift_from(graph, positions, rank, id, delta) do
    layer = graph.layers[rank]
    index = Enum.find_index(layer, &(&1 == id))

    layer
    |> Enum.drop(index)
    |> Enum.reduce(positions, &Map.update!(&2, &1, fn at -> at + delta end))
  end

  defp shift_cluster(graph, positions, cluster, delta) do
    Enum.reduce(graph.layers, positions, fn {_rank, layer}, positions ->
      case Enum.find_index(layer, &(cluster in graph.items[&1].path)) do
        nil ->
          positions

        index ->
          layer
          |> Enum.drop(index)
          |> Enum.reduce(positions, &Map.update!(&2, &1, fn at -> at + delta end))
      end
    end)
  end

  defp normalize_positions(graph, positions, config) do
    lefts = Enum.map(graph.items, fn {id, item} -> positions[id] - item.lo end)

    cluster_lefts =
      graph |> cluster_extents(positions, config) |> Map.values() |> Enum.map(&elem(&1, 0))

    least = Enum.min(lefts ++ cluster_lefts, fn -> 0 end)
    Map.new(positions, fn {id, at} -> {id, at - least} end)
  end

  # -- 5. route -----------------------------------------------------------------------------

  defp route(graph, config) do
    heights =
      Map.new(0..graph.depth//1, fn rank ->
        layer = graph.layers[rank]
        size = layer |> Enum.map(&graph.items[&1].size) |> Enum.max(fn -> 0 end)
        size = if layer != [] and rem(rank, 2) == 1, do: max(size, config.odd_rank), else: size
        {rank, size}
      end)

    graph = Map.put(graph, :heights, heights)
    segments = graph |> segments() |> Enum.group_by(&graph.items[&1.a].rank)

    channels =
      Map.new(0..(graph.depth - 1)//1, fn rank ->
        {rank, channel(graph, Map.get(segments, rank, []))}
      end)

    {coords, _y} = rank_coords(graph, channels, config)
    Map.merge(graph, %{channels: channels, coords: coords})
  end

  # Each edge's pieces from one layer to the next.
  defp segments(graph) do
    Enum.flat_map(graph.edges, fn edge ->
      chain = graph.chains[edge.index]

      chain
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] ->
        %{
          index: edge.index,
          a: a,
          b: b,
          x1: exit_at(graph, edge, a),
          x2: entry_at(graph, edge, b),
          up_mark: a == hd(chain) and upper_mark(edge) != nil,
          down_mark: b == List.last(chain) and lower_mark(edge) != nil
        }
      end)
    end)
  end

  # The edges between a layer and the next: which turn, on which track,
  # and whether arrowheads need a row of their own.
  defp channel(graph, segments) do
    uppers = Enum.frequencies_by(segments, &{&1.a, &1.x1})
    lowers = Enum.frequencies_by(segments, &{&1.b, &1.x2})

    keys =
      Map.new(segments, fn segment ->
        key =
          cond do
            uppers[{segment.a, segment.x1}] > 1 -> {:up, segment.a, segment.x1}
            lowers[{segment.b, segment.x2}] > 1 -> {:down, segment.b, segment.x2}
            true -> {:one, segment.index}
          end

        {{segment.index, segment.a}, key}
      end)

    {keys, doglegs} = untangle(segments, keys, %{})
    tracks = segments |> nets(keys, doglegs) |> assign_tracks(doglegs)

    up_row =
      Enum.any?(segments, fn segment ->
        segment.up_mark and touches_bottom?(graph, segment.a)
      end)

    down_row =
      Enum.any?(segments, fn segment ->
        segment.down_mark and touches_top?(graph, segment.b)
      end)

    %{
      keys: keys,
      doglegs: doglegs,
      tracks: tracks,
      track_count: tracks |> Map.values() |> Enum.max(fn -> -1 end) |> Kernel.+(1),
      up_row: up_row,
      down_row: down_row
    }
  end

  defp upper_mark(edge), do: if(edge.reversed, do: edge.head, else: edge.tail)
  defp lower_mark(edge), do: if(edge.reversed, do: edge.tail, else: edge.head)

  defp exit_at(graph, edge, id) do
    if graph.items[id].kind == :node,
      do: graph.positions[id] + graph.offsets[{edge.index, :down}],
      else: graph.positions[id]
  end

  defp entry_at(graph, edge, id) do
    if graph.items[id].kind == :node,
      do: graph.positions[id] + graph.offsets[{edge.index, :up}],
      else: graph.positions[id]
  end

  defp offset(graph, id) do
    item = graph.items[id]
    if item.kind == :node, do: div(graph.heights[item.rank] - item.size, 2), else: 0
  end

  defp touches_top?(graph, id), do: offset(graph, id) == 0

  defp touches_bottom?(graph, id) do
    item = graph.items[id]
    offset(graph, id) + item.size == graph.heights[item.rank]
  end

  # The segments sharing a key, as one net: one line along a track, from
  # its leftmost pin to its rightmost. Straight nets need no track. A
  # dogleg is two nets, the upper turning down at its column `m` to the
  # lower.
  defp nets(segments, keys, doglegs) do
    {bent, plain} = Enum.split_with(segments, &Map.has_key?(doglegs, {&1.index, &1.a}))

    halves =
      Enum.flat_map(bent, fn segment ->
        m = doglegs[{segment.index, segment.a}]

        [
          net({:upper, segment.index}, [segment.x1, m], [segment.x1], []),
          net({:lower, segment.index}, [m, segment.x2], [], [segment.x2])
        ]
      end)

    plain
    |> Enum.group_by(&keys[{&1.index, &1.a}])
    |> Enum.map(fn {key, segments} ->
      xs = Enum.flat_map(segments, &[&1.x1, &1.x2])
      net(key, xs, Enum.map(segments, & &1.x1), Enum.map(segments, & &1.x2))
    end)
    |> Enum.filter(&(&1.left < &1.right))
    |> Enum.concat(halves)
  end

  defp net(key, xs, tops, bottoms) do
    %{
      key: key,
      size: length(tops) + length(bottoms),
      left: Enum.min(xs),
      right: Enum.max(xs),
      tops: MapSet.new(tops),
      bottoms: MapSet.new(bottoms)
    }
  end

  # A net whose line comes down where another net's line goes on down
  # must run above it; a dogleg's upper half runs above its lower half.
  defp above(nets, doglegs) do
    halves =
      for {{index, _a}, _m} <- doglegs, into: %{}, do: {{{:upper, index}, {:lower, index}}, true}

    for a <- nets,
        b <- nets,
        a.key != b.key,
        not MapSet.disjoint?(a.tops, b.bottoms),
        into: halves,
        do: {{a.key, b.key}, true}
  end

  # Nets that must each run above the other would share a line. The
  # biggest net in such a cycle splits into its edges; when only single
  # edges are left, one of them turns twice (a dogleg) through a column
  # no pin uses, so the other runs between its turns.
  defp untangle(segments, keys, doglegs) do
    nets = nets(segments, keys, doglegs)
    tangled = cyclic(nets, above(nets, doglegs))

    case Enum.filter(tangled, &(&1.size > 2)) do
      [] ->
        with [_ | _] <- tangled,
             {segment, m} <- dogleg(segments, tangled, doglegs) do
          untangle(segments, keys, Map.put(doglegs, {segment.index, segment.a}, m))
        else
          _ -> {keys, doglegs}
        end

      multiple ->
        net = Enum.max_by(multiple, & &1.size)

        keys
        |> Map.new(fn {{index, _a} = segment, key} ->
          {segment, if(key == net.key, do: {:one, index}, else: key)}
        end)
        |> then(&untangle(segments, &1, doglegs))
    end
  end

  # A single edge on a cycle and a free column for it to turn in: between
  # its ends if there is one, or else just outside them.
  defp dogleg(segments, tangled, doglegs) do
    pins =
      segments
      |> Enum.flat_map(&[&1.x1, &1.x2])
      |> Enum.concat(Map.values(doglegs))
      |> MapSet.new()

    singles = for %{key: {:one, index}} <- tangled, into: MapSet.new(), do: index

    segments
    |> Enum.filter(
      &(MapSet.member?(singles, &1.index) and not Map.has_key?(doglegs, {&1.index, &1.a}))
    )
    |> Enum.find_value(fn segment ->
      step = if segment.x2 > segment.x1, do: 1, else: -1
      between = Enum.map(1..(abs(segment.x2 - segment.x1) - 1)//1, &(segment.x1 + &1 * step))
      outside = Enum.flat_map(1..3, &[segment.x1 - &1 * step, segment.x2 + &1 * step])

      case Enum.find(between ++ outside, &(not MapSet.member?(pins, &1))) do
        nil -> nil
        m -> {segment, m}
      end
    end)
  end

  # The nets on a cycle: what is left once nets with nothing above them,
  # or nothing below, are taken away, again and again.
  defp cyclic(nets, above) do
    loose =
      Enum.filter(nets, fn net ->
        not Enum.any?(nets, &Map.has_key?(above, {&1.key, net.key})) or
          not Enum.any?(nets, &Map.has_key?(above, {net.key, &1.key}))
      end)

    if loose == [], do: nets, else: cyclic(nets -- loose, above)
  end

  defp assign_tracks(nets, doglegs), do: tracks(nets, above(nets, doglegs), %{}, 0)

  defp tracks([], _above, assigned, _track), do: assigned

  defp tracks(nets, above, assigned, track) do
    ready =
      Enum.filter(nets, fn net ->
        Enum.all?(nets, fn other ->
          other.key == net.key or not Map.has_key?(above, {other.key, net.key})
        end)
      end)

    ready = if ready == [], do: nets, else: ready

    {placed, _right} =
      ready
      |> Enum.sort_by(&{&1.left, &1.right})
      |> Enum.reduce({[], nil}, fn net, {placed, right} ->
        if is_nil(right) or net.left > right + 1,
          do: {[net | placed], net.right},
          else: {placed, right}
      end)

    keys = MapSet.new(placed, & &1.key)
    assigned = Enum.reduce(placed, assigned, &Map.put(&2, &1.key, track))
    tracks(Enum.reject(nets, &MapSet.member?(keys, &1.key)), above, assigned, track + 1)
  end

  # Rows along the ranks: each layer, then the rows between it and the
  # next: an arrowhead row, subgraph bottoms, tracks, subgraph tops and
  # another arrowhead row.
  defp rank_coords(graph, channels, config) do
    # Subgraphs opening or closing together share a row per depth.
    clusters = Map.values(graph.clusters)

    opening = fn rank ->
      clusters
      |> Enum.filter(&(&1.low == rank))
      |> Enum.group_by(&length(&1.path))
      |> Enum.sort()
      |> Enum.map(&elem(&1, 1))
    end

    closing = fn rank ->
      clusters
      |> Enum.filter(&(&1.high == rank))
      |> Enum.group_by(&length(&1.path))
      |> Enum.sort(:desc)
      |> Enum.map(&elem(&1, 1))
    end

    coords = %{ranks: %{}, tracks: %{}, up_rows: %{}, down_rows: %{}, tops: %{}, bottoms: %{}}
    {coords, y} = open_clusters(coords, opening.(0), 0, config)

    Enum.reduce(0..graph.depth//1, {coords, y}, fn rank, {coords, y} ->
      coords = put_in(coords, [:ranks, rank], y)
      y = y + graph.heights[rank]
      channel = Map.get(channels, rank, %{up_row: false, down_row: false, track_count: 0})

      {coords, y} =
        if channel.up_row, do: {put_in(coords, [:up_rows, rank], y), y + 1}, else: {coords, y}

      {coords, y} = close_clusters(coords, closing.(rank), y, config)
      # Sideways, a turn right at a node's border would crowd it.
      y = if channel.track_count > 0 and not config.vertical, do: y + 1, else: y
      coords = put_in(coords, [:tracks, rank], y)
      y = y + channel.track_count
      {coords, y} = open_clusters(coords, opening.(rank + 1), y, config)

      if channel.down_row, do: {put_in(coords, [:down_rows, rank], y), y + 1}, else: {coords, y}
    end)
  end

  defp open_clusters(coords, groups, y, config) do
    Enum.reduce(groups, {coords, y}, fn group, {coords, y} ->
      coords = Enum.reduce(group, coords, &put_in(&2, [:tops, &1.id], y))
      {coords, y + 1 + config.cluster_rank}
    end)
  end

  defp close_clusters(coords, groups, y, config) do
    Enum.reduce(groups, {coords, y}, fn group, {coords, y} ->
      y = y + config.cluster_rank

      # Sideways, the title runs along the ranks; it needs the room.
      y =
        if config.vertical,
          do: y,
          else: Enum.reduce(group, y, &max(&2, coords.tops[&1.id] + Label.width(&1.title) + 5))

      coords = Enum.reduce(group, coords, &put_in(&2, [:bottoms, &1.id], y))
      {coords, y + 1}
    end)
  end

  # -- geometry -----------------------------------------------------------------------------

  defp geometry(graph, config) do
    coords = graph.coords
    extents = cluster_extents(graph, graph.positions, config)

    length =
      [
        Enum.map(graph.items, fn {id, item} ->
          coords.ranks[item.rank] + offset(graph, id) + item.size
        end),
        Enum.map(coords.bottoms, fn {_id, y} -> y + 1 end)
      ]
      |> Enum.concat()
      |> Enum.max(fn -> 0 end)

    breadth =
      [
        Enum.map(graph.items, fn {id, item} -> graph.positions[id] + item.hi + 1 end),
        Enum.map(extents, fn {_id, {_left, right}} -> right + 1 end)
      ]
      |> Enum.concat()
      |> Enum.max(fn -> 0 end)

    turn = turner(config.direction, length)

    nodes =
      graph.items
      |> Map.values()
      |> Enum.filter(&(&1.kind == :node))
      |> Enum.map(fn item ->
        {x, y, w, h} = turn_rect(turn, box(graph, item), config)
        %{node: item.node, lines: item.lines, x: x, y: y, w: w, h: h}
      end)

    labels =
      graph.items
      |> Map.values()
      |> Enum.filter(&(&1.kind == :label))
      |> Enum.map(fn item ->
        {x, y, w, h} = turn_rect(turn, box(graph, item), config)
        %{lines: item.lines, x: x, y: y, w: w, h: h}
      end)

    clusters =
      Enum.map(graph.clusters, fn {id, cluster} ->
        {left, right} = extents[id]
        top = coords.tops[id]
        bottom = coords.bottoms[id]
        {x, y, w, h} = turn_rect(turn, {left, top, right - left + 1, bottom - top + 1}, config)
        %{id: id, title: cluster.title, x: x, y: y, w: w, h: h, depth: length(cluster.path)}
      end)
      |> Enum.sort_by(& &1.depth)

    edges =
      Enum.map(graph.edges, fn edge ->
        points = graph |> edge_points(edge) |> Enum.map(turn)
        %{edge: edge, points: points}
      end)

    loops =
      graph.items
      |> Map.values()
      |> Enum.filter(&(&1.kind == :node and &1.loops != []))
      |> Enum.map(fn item ->
        {c, r, w, _h} = box(graph, item)
        right = c + w - 1

        points =
          Enum.map([{right, r + 1}, {right + 2, r + 1}, {right + 2, r + 2}, {right, r + 2}], turn)

        %{edge: hd(item.loops), points: points, label: item.loop_label}
      end)

    {width, height} = if config.vertical, do: {breadth, length}, else: {length, breadth}

    %{
      direction: config.direction,
      vertical: config.vertical,
      width: width,
      height: height,
      nodes: nodes,
      labels: labels,
      clusters: clusters,
      edges: edges,
      loops: loops
    }
  end

  # An item's box as {cross, rank, across, along}.
  defp box(graph, item) do
    rank = graph.coords.ranks[item.rank] + offset(graph, item.id)
    centre = graph.positions[item.id]
    {centre - item.lo, rank, item.lo + item.box_hi + 1, item.size}
  end

  defp edge_points(graph, edge) do
    chain = graph.chains[edge.index]
    [first | _] = chain
    start = {exit_at(graph, edge, first), bottom(graph, first)}

    rest =
      chain
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.flat_map(fn [a, b] ->
        rank = graph.items[a].rank
        channel = graph.channels[rank]
        x1 = exit_at(graph, edge, a)
        x2 = entry_at(graph, edge, b)
        y2 = top(graph, b)

        first_track = graph.coords.tracks[rank]

        turn =
          cond do
            x1 == x2 ->
              []

            m = channel.doglegs[{edge.index, a}] ->
              upper = first_track + channel.tracks[{:upper, edge.index}]
              lower = first_track + channel.tracks[{:lower, edge.index}]
              [{x1, upper}, {m, upper}, {m, lower}, {x2, lower}]

            true ->
              track = first_track + Map.fetch!(channel.tracks, channel.keys[{edge.index, a}])
              [{x1, track}, {x2, track}]
          end

        through = if graph.items[b].kind == :node, do: [], else: [{x2, bottom(graph, b)}]
        turn ++ [{x2, y2} | through]
      end)

    [start | rest]
  end

  # The first and last rows of an item along the ranks: a node's borders,
  # or a dummy's whole layer.
  defp top(graph, id) do
    item = graph.items[id]
    graph.coords.ranks[item.rank] + offset(graph, id)
  end

  defp bottom(graph, id) do
    item = graph.items[id]

    if item.kind == :node,
      do: top(graph, id) + item.size - 1,
      else: graph.coords.ranks[item.rank] + graph.heights[item.rank] - 1
  end

  # From {cross, rank} to {x, y} for the chart's direction.
  defp turner(:tb, _length), do: fn {c, r} -> {c, r} end
  defp turner(:bt, length), do: fn {c, r} -> {c, length - 1 - r} end
  defp turner(:lr, _length), do: fn {c, r} -> {r, c} end
  defp turner(:rl, length), do: fn {c, r} -> {length - 1 - r, c} end

  defp turn_rect(turn, {c, r, across, along}, _config) do
    {x1, y1} = turn.({c, r})
    {x2, y2} = turn.({c + across - 1, r + along - 1})
    {min(x1, x2), min(y1, y2), abs(x2 - x1) + 1, abs(y2 - y1) + 1}
  end
end

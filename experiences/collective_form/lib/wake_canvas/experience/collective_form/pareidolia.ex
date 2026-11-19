defmodule WakeCanvas.Experience.CollectiveForm.Pareidolia do
  @moduledoc """
  Builds a bounded, portable interpretation request from a Collective Form
  snapshot and validates an interpreter response against that exact request.

  The files live below the Experience instance directory. The interpreter may
  be a developer working with Codex today or a local service later; both use
  the same request and response contract.
  """

  @directory "pareidolia"
  @minimum_connections 3
  @absolute_maximum_candidates 64
  @absolute_maximum_interpretations 12
  @candidates_per_sheet 16
  @maximum_contours 8
  @maximum_contour_points 64

  def prepare(data_dir, snapshot) do
    candidates = candidates(snapshot)

    if candidates == [] do
      {:error, :network_too_small}
    else
      fingerprint = fingerprint(snapshot)
      analysis_id = "#{snapshot.cycle_id}-#{String.slice(fingerprint, 0, 12)}"
      directory = Path.join(data_dir, @directory)
      File.mkdir_p!(directory)
      interpretation_limit = interpretation_limit(length(candidates))
      sheet_names = candidate_sheet_names(candidates)

      request = %{
        contract_version: 1,
        analysis_id: analysis_id,
        network_fingerprint: fingerprint,
        created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        candidate_sheet: List.first(sheet_names),
        candidate_sheets: sheet_names,
        maximum_interpretations: interpretation_limit,
        instructions:
          "Find the strongest recognizable forms already present across every candidate sheet. Select at most #{interpretation_limit} diverse readings; do not invent connections. Optionally add bounded normalized contour strokes that make each reading visually clear.",
        candidates: candidates,
        network: request_network(snapshot)
      }

      response_template = %{
        analysis_id: analysis_id,
        network_fingerprint: fingerprint,
        interpretations: [
          %{
            candidate_id: List.first(candidates).id,
            title: "Recognizable form",
            confidence: 0.75,
            contours: [
              %{closed: true, points: [[0.3, 0.3], [0.7, 0.3], [0.7, 0.7], [0.3, 0.7]]}
            ]
          }
        ]
      }

      with :ok <-
             atomic_write(
               Path.join(directory, "request.json"),
               Jason.encode_to_iodata!(request, pretty: true)
             ),
           :ok <-
             write_candidate_sheets(directory, snapshot, candidates, sheet_names),
           :ok <-
             atomic_write(
               Path.join(directory, "response.example.json"),
               Jason.encode_to_iodata!(response_template, pretty: true)
             ),
           :ok <- remove_stale_response(directory) do
        {:ok,
         %{analysis_id: analysis_id, directory: directory, candidate_count: length(candidates)}}
      end
    end
  end

  def status(data_dir) do
    directory = Path.join(data_dir, @directory)

    with {:ok, request} <- read_json(Path.join(directory, "request.json")),
         {:ok, response} <- read_json(Path.join(directory, "response.json")),
         {:ok, interpretations} <- validate_response(request, response) do
      %{
        status: "ready",
        analysisId: request["analysis_id"],
        networkFingerprint: request["network_fingerprint"],
        interpretations: interpretations,
        network: request["network"]
      }
    else
      {:error, :enoent} -> request_status(directory)
      {:error, reason} -> %{status: "invalid", error: format_error(reason)}
    end
  end

  def candidates(%{connections: connections, contributions: contributions})
      when length(connections) >= @minimum_connections do
    nodes =
      contributions
      |> Enum.filter(&(&1.state == "placed"))
      |> Map.new(&{&1.id, &1})

    edges =
      connections
      |> Enum.filter(&(Map.has_key?(nodes, &1.source_id) and Map.has_key?(nodes, &1.target_id)))
      |> Enum.sort_by(& &1.id)

    capacity = candidate_capacity(map_size(nodes), length(edges))
    sizes = candidate_sizes(length(edges))
    degrees = node_degrees(edges)
    seeds = distributed_seed_edges(edges, nodes, min(length(edges), capacity * 2))

    sizes
    |> Enum.map(fn size ->
      for {seed, index} <- Enum.with_index(seeds), mode <- [:local, :branching, :reaching] do
        grow_candidate(edges, nodes, degrees, seed, size, index, mode)
      end
    end)
    |> select_diverse_candidates(capacity)
    |> Enum.with_index(1)
    |> Enum.map(fn {connection_ids, id} -> %{id: id, connection_ids: connection_ids} end)
  end

  def candidates(_snapshot), do: []

  defp grow_candidate(edges, nodes, degrees, seed, target_size, salt, mode) do
    do_grow(
      edges,
      nodes,
      degrees,
      [seed],
      MapSet.new([seed.source_id, seed.target_id]),
      target_size,
      salt,
      mode
    )
    |> Enum.map(& &1.id)
    |> Enum.sort()
  end

  defp do_grow(_edges, _nodes, _degrees, selected, _node_ids, target_size, _salt, _mode)
       when length(selected) >= target_size,
       do: selected

  defp do_grow(edges, nodes, degrees, selected, node_ids, target_size, salt, mode) do
    selected_ids = MapSet.new(selected, & &1.id)

    next =
      edges
      |> Enum.reject(&MapSet.member?(selected_ids, &1.id))
      |> Enum.filter(
        &(MapSet.member?(node_ids, &1.source_id) or MapSet.member?(node_ids, &1.target_id))
      )
      |> Enum.min_by(
        &edge_growth_priority(&1, nodes, degrees, node_ids, salt, mode),
        fn -> nil end
      )

    case next do
      nil ->
        selected

      edge ->
        do_grow(
          edges,
          nodes,
          degrees,
          selected ++ [edge],
          node_ids |> MapSet.put(edge.source_id) |> MapSet.put(edge.target_id),
          target_size,
          salt,
          mode
        )
    end
  end

  defp edge_growth_priority(edge, nodes, degrees, node_ids, salt, mode) do
    new_node? =
      not (MapSet.member?(node_ids, edge.source_id) and
             MapSet.member?(node_ids, edge.target_id))

    degree = max(Map.get(degrees, edge.source_id, 0), Map.get(degrees, edge.target_id, 0))
    tie_breaker = {rem(edge.id + salt * 7, 29), edge.id}

    case mode do
      :branching ->
        {if(new_node?, do: 0, else: 1), -degree, edge_length(edge, nodes), tie_breaker}

      :reaching ->
        {if(new_node?, do: 0, else: 1), -edge_length(edge, nodes), -degree, tie_breaker}

      _ ->
        {if(new_node?, do: 0, else: 1), edge_length(edge, nodes), -degree, tie_breaker}
    end
  end

  defp candidate_capacity(node_count, edge_count) do
    cond do
      node_count >= 40 or edge_count >= 120 -> @absolute_maximum_candidates
      node_count >= 24 or edge_count >= 60 -> 48
      node_count >= 14 or edge_count >= 25 -> 32
      true -> 16
    end
  end

  defp candidate_sizes(edge_count) do
    [4, 7, 11, 16, 24, 36]
    |> Enum.map(&min(&1, edge_count))
    |> Enum.uniq()
  end

  defp node_degrees(edges) do
    Enum.reduce(edges, %{}, fn edge, degrees ->
      degrees
      |> Map.update(edge.source_id, 1, &(&1 + 1))
      |> Map.update(edge.target_id, 1, &(&1 + 1))
    end)
  end

  defp distributed_seed_edges([], _nodes, _limit), do: []

  defp distributed_seed_edges(edges, nodes, limit) do
    first =
      Enum.min_by(edges, fn edge ->
        midpoint = edge_midpoint(edge, nodes)
        {midpoint.x + midpoint.y, midpoint.x, midpoint.y, edge.id}
      end)

    select_seed_edges(edges, nodes, [first], MapSet.new([first.id]), limit)
  end

  defp select_seed_edges(_edges, _nodes, selected, _selected_ids, limit)
       when length(selected) >= limit,
       do: selected

  defp select_seed_edges(edges, nodes, selected, selected_ids, limit) do
    selected_midpoints = Enum.map(selected, &edge_midpoint(&1, nodes))

    next =
      edges
      |> Enum.reject(&MapSet.member?(selected_ids, &1.id))
      |> Enum.max_by(
        fn edge ->
          midpoint = edge_midpoint(edge, nodes)

          separation =
            selected_midpoints
            |> Enum.map(&squared_distance(midpoint, &1))
            |> Enum.min(fn -> 0.0 end)

          {separation + edge_length(edge, nodes) * 0.025, -edge.id}
        end,
        fn -> nil end
      )

    case next do
      nil ->
        selected

      edge ->
        select_seed_edges(
          edges,
          nodes,
          selected ++ [edge],
          MapSet.put(selected_ids, edge.id),
          limit
        )
    end
  end

  defp edge_midpoint(edge, nodes) do
    source = nodes[edge.source_id]
    target = nodes[edge.target_id]
    %{x: (source.x + target.x) / 2, y: (source.y + target.y) / 2}
  end

  defp squared_distance(left, right),
    do: :math.pow(left.x - right.x, 2) + :math.pow(left.y - right.y, 2)

  defp select_diverse_candidates(groups, capacity) do
    groups =
      Enum.map(groups, &(&1 |> Enum.reject(fn candidate -> candidate == [] end) |> Enum.uniq()))

    quota = ceil(capacity / max(length(groups), 1))

    selected =
      Enum.reduce(groups, [], fn group, selected ->
        append_diverse(group, selected, min(capacity, length(selected) + quota))
      end)

    groups
    |> Enum.concat()
    |> append_diverse(selected, capacity)
    |> Enum.take(capacity)
  end

  defp append_diverse(candidates, selected, target) do
    Enum.reduce_while([0.42, 0.58, 0.72, 0.86, 1.01], selected, fn threshold, accepted ->
      next = append_at_threshold(candidates, accepted, target, threshold)
      if length(next) >= target, do: {:halt, next}, else: {:cont, next}
    end)
  end

  defp append_at_threshold(candidates, selected, target, threshold) do
    Enum.reduce_while(candidates, selected, fn candidate, accepted ->
      cond do
        length(accepted) >= target ->
          {:halt, accepted}

        candidate in accepted ->
          {:cont, accepted}

        Enum.all?(accepted, &(candidate_overlap(candidate, &1) <= threshold)) ->
          {:cont, accepted ++ [candidate]}

        true ->
          {:cont, accepted}
      end
    end)
  end

  defp candidate_overlap(left, right) do
    left = MapSet.new(left)
    right = MapSet.new(right)
    union_size = MapSet.union(left, right) |> MapSet.size()

    if union_size == 0,
      do: 0.0,
      else: MapSet.intersection(left, right) |> MapSet.size() |> Kernel./(union_size)
  end

  defp edge_length(edge, nodes) do
    source = nodes[edge.source_id]
    target = nodes[edge.target_id]
    :math.sqrt(:math.pow(source.x - target.x, 2) + :math.pow(source.y - target.y, 2))
  end

  defp fingerprint(snapshot) do
    canonical = %{
      cycle_id: snapshot.cycle_id,
      contributions:
        snapshot.contributions
        |> Enum.filter(&(&1.state == "placed"))
        |> Enum.map(&[&1.id, rounded(&1.x), rounded(&1.y)]),
      connections:
        Enum.map(snapshot.connections, &[&1.id, &1.source_id, &1.target_id, &1.path_seed])
    }

    :crypto.hash(:sha256, Jason.encode!(canonical)) |> Base.encode16(case: :lower)
  end

  defp request_network(snapshot) do
    %{
      contributions:
        snapshot.contributions
        |> Enum.filter(&(&1.state == "placed"))
        |> Enum.map(&Map.take(&1, [:id, :x, :y, :color, :size])),
      connections:
        Enum.map(
          snapshot.connections,
          &Map.take(&1, [:id, :source_id, :target_id, :path_seed])
        )
    }
  end

  defp rounded(value), do: Float.round(value * 1.0, 5)

  defp interpretation_limit(candidate_count) do
    cond do
      candidate_count >= 64 -> @absolute_maximum_interpretations
      candidate_count >= 48 -> 10
      candidate_count >= 32 -> 8
      true -> 4
    end
  end

  defp candidate_sheet_names(candidates) do
    candidates
    |> Enum.chunk_every(@candidates_per_sheet)
    |> Enum.with_index(1)
    |> Enum.map(fn
      {_candidates, 1} -> "candidate-sheet.svg"
      {_candidates, index} -> "candidate-sheet-#{index}.svg"
    end)
  end

  defp write_candidate_sheets(directory, snapshot, candidates, sheet_names) do
    candidates
    |> Enum.chunk_every(@candidates_per_sheet)
    |> Enum.zip(sheet_names)
    |> Enum.reduce_while(:ok, fn {sheet_candidates, sheet_name}, :ok ->
      case atomic_write(
             Path.join(directory, sheet_name),
             candidate_sheet(snapshot, sheet_candidates)
           ) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp candidate_sheet(snapshot, candidates) do
    nodes = Map.new(snapshot.contributions, &{&1.id, &1})
    edges = Map.new(snapshot.connections, &{&1.id, &1})
    columns = 4
    cell_width = 320
    cell_height = 230
    rows = ceil(length(candidates) / columns)

    cells =
      candidates
      |> Enum.with_index()
      |> Enum.map_join(fn {candidate, index} ->
        candidate_svg(candidate, index, nodes, edges, cell_width, cell_height, columns)
      end)

    """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{columns * cell_width} #{rows * cell_height}" width="#{columns * cell_width}" height="#{rows * cell_height}">
      <rect width="100%" height="100%" fill="#050806"/>
      <style>text{font-family:system-ui,sans-serif}.edge{fill:none;stroke:#d9e8c2;stroke-linecap:round}.node{fill:#f3f0d5}</style>
      #{cells}
    </svg>
    """
  end

  defp candidate_svg(candidate, index, nodes, edges, cell_width, cell_height, columns) do
    candidate_edges = Enum.map(candidate.connection_ids, &edges[&1]) |> Enum.reject(&is_nil/1)
    node_ids = candidate_edges |> Enum.flat_map(&[&1.source_id, &1.target_id]) |> Enum.uniq()
    points = Enum.map(node_ids, &nodes[&1]) |> Enum.reject(&is_nil/1)
    bounds = bounds(points)
    offset_x = rem(index, columns) * cell_width
    offset_y = div(index, columns) * cell_height

    lines =
      Enum.map_join(candidate_edges, fn edge ->
        source =
          project(nodes[edge.source_id], bounds, offset_x, offset_y, cell_width, cell_height)

        target =
          project(nodes[edge.target_id], bounds, offset_x, offset_y, cell_width, cell_height)

        curve = (rem(edge.path_seed, 21) - 10) * 0.8
        control_x = (source.x + target.x) / 2 - (target.y - source.y) * curve / 100
        control_y = (source.y + target.y) / 2 + (target.x - source.x) * curve / 100

        ~s(<path class="edge" d="M #{source.x} #{source.y} Q #{control_x} #{control_y} #{target.x} #{target.y}" stroke-width="#{1.4 + rem(edge.path_seed, 5) * 0.35}" opacity="0.84"/>)
      end)

    dots =
      Enum.map_join(points, fn point ->
        projected = project(point, bounds, offset_x, offset_y, cell_width, cell_height)
        ~s(<circle class="node" cx="#{projected.x}" cy="#{projected.y}" r="3.2"/>)
      end)

    """
    <g>
      <rect x="#{offset_x + 8}" y="#{offset_y + 8}" width="#{cell_width - 16}" height="#{cell_height - 16}" rx="10" fill="#09100b" stroke="#30402f"/>
      <text x="#{offset_x + 22}" y="#{offset_y + 31}" fill="#aebca4" font-size="14">Candidate #{candidate.id} · #{length(candidate.connection_ids)} connections</text>
      #{lines}
      #{dots}
    </g>
    """
  end

  defp bounds([]), do: %{min_x: 0.0, max_x: 1.0, min_y: 0.0, max_y: 1.0}

  defp bounds(points) do
    xs = Enum.map(points, & &1.x)
    ys = Enum.map(points, & &1.y)
    %{min_x: Enum.min(xs), max_x: Enum.max(xs), min_y: Enum.min(ys), max_y: Enum.max(ys)}
  end

  defp project(point, bounds, offset_x, offset_y, cell_width, cell_height) do
    available_width = cell_width - 54
    available_height = cell_height - 72
    width = max(bounds.max_x - bounds.min_x, 0.05)
    height = max(bounds.max_y - bounds.min_y, 0.05)
    scale = min(available_width / width, available_height / height)
    drawing_width = width * scale
    drawing_height = height * scale

    %{
      x:
        Float.round(
          offset_x + 27 + (available_width - drawing_width) / 2 + (point.x - bounds.min_x) * scale,
          2
        ),
      y:
        Float.round(
          offset_y + 48 + (available_height - drawing_height) / 2 +
            (point.y - bounds.min_y) * scale,
          2
        )
    }
  end

  defp validate_response(request, response) do
    candidate_map = Map.new(request["candidates"] || [], &{&1["id"], &1["connection_ids"]})

    cond do
      response["analysis_id"] != request["analysis_id"] ->
        {:error, :analysis_id_mismatch}

      response["network_fingerprint"] != request["network_fingerprint"] ->
        {:error, :fingerprint_mismatch}

      not is_list(response["interpretations"]) ->
        {:error, :invalid_interpretations}

      true ->
        validate_interpretations(
          response["interpretations"],
          candidate_map,
          validated_interpretation_limit(request["maximum_interpretations"])
        )
    end
  end

  defp validate_interpretations(interpretations, candidate_map, limit) do
    interpretations
    |> Enum.take(limit)
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, accepted} ->
      candidate_id = item["candidate_id"]
      title = item["title"]
      confidence = item["confidence"]

      with true <- Map.has_key?(candidate_map, candidate_id),
           true <- is_binary(title) and String.trim(title) != "",
           true <- is_number(confidence) and confidence >= 0 and confidence <= 1,
           {:ok, contours} <- validate_contours(item["contours"]) do
        interpretation = %{
          candidateId: candidate_id,
          title: String.slice(String.trim(title), 0, 120),
          confidence: confidence,
          connectionIds: candidate_map[candidate_id],
          contours: contours
        }

        {:cont, {:ok, accepted ++ [interpretation]}}
      else
        _ -> {:halt, {:error, :invalid_interpretation}}
      end
    end)
  end

  defp validated_interpretation_limit(limit)
       when is_integer(limit) and limit >= 1 and limit <= @absolute_maximum_interpretations,
       do: limit

  defp validated_interpretation_limit(_limit), do: 4

  defp validate_contours(nil), do: {:ok, []}

  defp validate_contours(contours)
       when is_list(contours) and length(contours) <= @maximum_contours do
    Enum.reduce_while(contours, {:ok, []}, fn contour, {:ok, accepted} ->
      points = contour["points"]
      closed = contour["closed"]

      if is_boolean(closed) and valid_contour_points?(points, closed) do
        normalized = Enum.map(points, fn [x, y] -> [x * 1.0, y * 1.0] end)
        {:cont, {:ok, accepted ++ [%{closed: closed, points: normalized}]}}
      else
        {:halt, {:error, :invalid_contour}}
      end
    end)
  end

  defp validate_contours(_contours), do: {:error, :invalid_contour}

  defp valid_contour_points?(points, closed) when is_list(points) do
    minimum = if closed, do: 3, else: 2

    length(points) >= minimum and length(points) <= @maximum_contour_points and
      Enum.all?(points, fn
        [x, y] when is_number(x) and is_number(y) ->
          x >= 0 and x <= 1 and y >= 0 and y <= 1

        _ ->
          false
      end)
  end

  defp valid_contour_points?(_points, _closed), do: false

  defp request_status(directory) do
    case read_json(Path.join(directory, "request.json")) do
      {:ok, request} ->
        %{
          status: "awaiting_interpretation",
          analysisId: request["analysis_id"],
          candidateCount: length(request["candidates"] || [])
        }

      _ ->
        %{status: "not_prepared"}
    end
  end

  defp read_json(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, decoded} <- Jason.decode(contents) do
      {:ok, decoded}
    end
  end

  defp remove_stale_response(directory) do
    case File.rm(Path.join(directory, "response.json")) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      other -> other
    end
  end

  defp atomic_write(path, contents) do
    temporary = path <> ".tmp"

    with :ok <- File.write(temporary, contents),
         :ok <- remove_existing(path),
         :ok <- File.rename(temporary, path) do
      :ok
    end
  end

  defp remove_existing(path) do
    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      other -> other
    end
  end

  defp format_error(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_error(reason), do: inspect(reason)
end

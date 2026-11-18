defmodule WakeCanvas.Experience.CollectiveForm.Store do
  alias WakeCanvas.Experience.CollectiveForm.Repo

  @growth_duration_ms 18_000
  @max_direct_connections 3
  @minimum_local_radius 0.22
  @maximum_local_radius 0.42
  @background_reach 0.68
  @maximum_route_degree 8
  @maintenance_retired_threshold 2_000
  @maintenance_database_threshold 25 * 1_024 * 1_024
  @completed_cycles_to_keep 10

  def migrate(database_path) do
    with_raw_repo(database_path, fn ->
      ensure_schema!()
      :ok
    end)
  end

  def snapshot(database_path) do
    with_repo(database_path, fn ->
      cycle_id = current_cycle_id!()

      contributions =
        query!(
          "SELECT id, title, color, size, x, y, state, source, inserted_at, updated_at FROM contributions WHERE cycle_id = ? ORDER BY id",
          [cycle_id]
        ).rows
        |> Enum.map(&contribution/1)

      connections =
        query!(
          "SELECT id, source_id, target_id, path_seed, growth_started_at, growth_duration_ms, algorithm_version FROM connections WHERE cycle_id = ? AND state = 'active' ORDER BY id",
          [cycle_id]
        ).rows
        |> Enum.map(&connection/1)

      %{cycle_id: cycle_id, contributions: contributions, connections: connections}
    end)
  end

  def maintain(database_path, options \\ []) do
    retired_threshold =
      Keyword.get(options, :retired_threshold, @maintenance_retired_threshold)

    database_threshold =
      Keyword.get(options, :database_threshold, @maintenance_database_threshold)

    completed_cycles_to_keep =
      Keyword.get(options, :completed_cycles_to_keep, @completed_cycles_to_keep)

    with_write_repo(database_path, fn ->
      cycle_id = current_cycle_id!()

      retired_before =
        scalar!("SELECT COUNT(*) FROM connections WHERE cycle_id = ? AND state = 'retired'", [
          cycle_id
        ])

      completed_before = scalar!("SELECT COUNT(*) FROM cycles WHERE status = 'complete'")
      live_bytes_before = live_database_bytes!()

      compact? =
        retired_before > retired_threshold or live_bytes_before > database_threshold

      retired_deleted =
        if compact? do
          query!(
            """
            DELETE FROM connections
            WHERE cycle_id = ?
              AND state = 'retired'
              AND id NOT IN (
                SELECT MAX(id)
                FROM connections
                WHERE cycle_id = ? AND state = 'retired'
                GROUP BY MIN(source_id, target_id), MAX(source_id, target_id)
              )
            """,
            [cycle_id, cycle_id]
          ).num_rows
        else
          0
        end

      completed_cycle_ids =
        query!(
          "SELECT id FROM cycles WHERE status = 'complete' ORDER BY COALESCE(ended_at, started_at) DESC, id DESC LIMIT -1 OFFSET ?",
          [completed_cycles_to_keep]
        ).rows
        |> List.flatten()

      Enum.each(completed_cycle_ids, fn completed_cycle_id ->
        query!("DELETE FROM connections WHERE cycle_id = ?", [completed_cycle_id])
        query!("DELETE FROM contributions WHERE cycle_id = ?", [completed_cycle_id])
        query!("DELETE FROM cycles WHERE id = ?", [completed_cycle_id])
      end)

      retired_after =
        scalar!("SELECT COUNT(*) FROM connections WHERE cycle_id = ? AND state = 'retired'", [
          cycle_id
        ])

      %{
        compacted?: compact? or completed_cycle_ids != [],
        retired_before: retired_before,
        retired_after: retired_after,
        retired_deleted: retired_deleted,
        completed_cycles_before: completed_before,
        completed_cycles_deleted: length(completed_cycle_ids),
        live_bytes_before: live_bytes_before
      }
    end)
  end

  def add_contribution(database_path, attrs) do
    with_write_repo(database_path, fn ->
      cycle_id = current_cycle_id!()
      now = now()

      query!(
        "INSERT INTO contributions (cycle_id, title, color, size, state, source, inserted_at, updated_at) VALUES (?, ?, ?, ?, 'unplaced', 'operator', ?, ?)",
        [
          cycle_id,
          normalize_title(attrs["title"]),
          normalize_color(attrs["color"]),
          normalize_size(attrs["size"]),
          now,
          now
        ]
      )

      :ok
    end)
  end

  def evolve(database_path, at \\ DateTime.utc_now()) do
    with_write_repo(database_path, fn ->
      cycle_id = current_cycle_id!()

      nodes =
        query!(
          "SELECT id, x, y, updated_at FROM contributions WHERE cycle_id = ? AND state = 'placed' AND x IS NOT NULL AND y IS NOT NULL ORDER BY id",
          [cycle_id]
        ).rows

      node_positions =
        Map.new(nodes, fn [id, x, y, _updated_at] -> {id, {x, y}} end)

      preferred_pairs = nearest_pairs(nodes, 2)

      newest_node_id =
        nodes
        |> Enum.max_by(fn [id, _x, _y, updated_at] -> {timestamp_ms(updated_at), id} end, fn ->
          nil
        end)
        |> case do
          [id | _rest] -> id
          nil -> nil
        end

      existing_routes =
        query!(
          "SELECT id, source_id, target_id, path_seed, growth_started_at, growth_duration_ms FROM connections WHERE cycle_id = ? AND state = 'active'",
          [cycle_id]
        ).rows

      route_history =
        query!(
          "SELECT MIN(source_id, target_id), MAX(source_id, target_id), MAX(id), MAX(COALESCE(retired_at, growth_started_at)) FROM connections WHERE cycle_id = ? GROUP BY MIN(source_id, target_id), MAX(source_id, target_id)",
          [cycle_id]
        ).rows
        |> Map.new(fn [left, right, latest_id, last_event_at] ->
          {pair(left, right), %{generation: latest_id, last_event_at: last_event_at}}
        end)

      origin_counts =
        query!(
          "SELECT target_id, COUNT(*) FROM connections WHERE cycle_id = ? GROUP BY target_id",
          [cycle_id]
        ).rows
        |> Map.new(fn [node_id, count] -> {node_id, count} end)

      existing_pairs =
        existing_routes
        |> Enum.map(fn [_id, left, right, _seed, _started_at, _duration] -> pair(left, right) end)
        |> MapSet.new()

      degrees =
        Enum.reduce(existing_routes, %{}, fn [_id, left, right, _seed, _started_at, _duration],
                                             acc ->
          acc |> Map.update(left, 1, &(&1 + 1)) |> Map.update(right, 1, &(&1 + 1))
        end)

      now_ms = DateTime.to_unix(at, :millisecond)

      candidate =
        nodes
        |> route_candidates(
          cycle_id,
          existing_pairs,
          degrees,
          route_history,
          origin_counts,
          preferred_pairs,
          newest_node_id
        )
        |> Enum.filter(&(&1.due_at_ms <= now_ms))
        |> Enum.min_by(
          &{&1.arrival_priority, &1.proximity_priority, &1.minimum_degree, &1.maximum_degree,
           &1.origin_count, &1.distance, &1.due_at_ms},
          fn -> nil end
        )

      retirement =
        retirement_candidate(
          existing_routes,
          degrees,
          origin_counts,
          node_positions,
          preferred_pairs,
          now_ms
        )

      case {candidate, retirement} do
        {route, _retirement} when not is_nil(route) ->
          insert_route!(
            cycle_id,
            route.source_id,
            route.target_id,
            route.distance,
            route.seed,
            timestamp(at)
          )

          :changed

        {nil, route} when not is_nil(route) ->
          query!("UPDATE connections SET state = 'retired', retired_at = ? WHERE id = ?", [
            timestamp(at),
            route.id
          ])

          :changed

        {nil, nil} ->
          :unchanged
      end
    end)
  end

  def place_contribution(database_path, id, x, y) do
    with_write_repo(database_path, fn ->
      cycle_id = current_cycle_id!()
      x = clamp_coordinate(x)
      y = clamp_coordinate(y)

      query!(
        "UPDATE contributions SET x = ?, y = ?, state = 'placed', updated_at = ? WHERE id = ? AND cycle_id = ?",
        [x, y, now(), id, cycle_id]
      )

      query!("DELETE FROM connections WHERE cycle_id = ? AND (source_id = ? OR target_id = ?)", [
        cycle_id,
        id,
        id
      ])

      connect_contribution!(cycle_id, id, x, y)
      :ok
    end)
  end

  def remove_contribution(database_path, id) do
    with_write_repo(database_path, fn ->
      cycle_id = current_cycle_id!()

      query!(
        "UPDATE contributions SET state = 'removed', updated_at = ? WHERE id = ? AND cycle_id = ?",
        [now(), id, cycle_id]
      )

      query!("DELETE FROM connections WHERE cycle_id = ? AND (source_id = ? OR target_id = ?)", [
        cycle_id,
        id,
        id
      ])

      :ok
    end)
  end

  def unplace_contribution(database_path, id) do
    with_write_repo(database_path, fn ->
      cycle_id = current_cycle_id!()

      query!(
        "UPDATE contributions SET x = NULL, y = NULL, state = 'unplaced', updated_at = ? WHERE id = ? AND cycle_id = ?",
        [now(), id, cycle_id]
      )

      query!("DELETE FROM connections WHERE cycle_id = ? AND (source_id = ? OR target_id = ?)", [
        cycle_id,
        id,
        id
      ])

      :ok
    end)
  end

  def reset_cycle(database_path) do
    with_write_repo(database_path, fn ->
      query!("UPDATE cycles SET status = 'complete', ended_at = ? WHERE status = 'active'", [
        now()
      ])

      create_cycle!()
      :ok
    end)
  end

  defp connect_contribution!(cycle_id, id, x, y) do
    ranked_candidates =
      query!(
        "SELECT id, x, y FROM contributions WHERE cycle_id = ? AND state = 'placed' AND id != ? AND x IS NOT NULL AND y IS NOT NULL",
        [cycle_id, id]
      ).rows
      |> Enum.map(fn [other_id, other_x, other_y] ->
        {
          distance(x, y, other_x, other_y),
          other_id,
          :math.atan2(other_y - y, other_x - x)
        }
      end)
      |> Enum.sort()

    candidates = local_candidates(ranked_candidates, cycle_id, id)

    candidates
    |> Enum.with_index()
    |> Enum.each(fn {{candidate_distance, neighbour_id, _angle}, index} ->
      seed = :erlang.phash2({cycle_id, id, neighbour_id}, 2_147_483_647)
      delay_ms = growth_delay_ms(index, candidate_distance, seed)
      growth_started_at = now(delay_ms)
      growth_duration_ms = growth_duration_ms(candidate_distance, seed)

      # The arriving node initiates the first route. Alternating the remaining
      # routes makes nearby established nodes visibly respond to its arrival.
      {source_id, target_id} =
        if rem(index, 2) == 0, do: {id, neighbour_id}, else: {neighbour_id, id}

      insert_route!(
        cycle_id,
        source_id,
        target_id,
        candidate_distance,
        seed,
        growth_started_at,
        growth_duration_ms
      )
    end)
  end

  defp route_candidates(
         nodes,
         cycle_id,
         existing_pairs,
         degrees,
         route_history,
         origin_counts,
         preferred_pairs,
         newest_node_id
       ) do
    nodes
    |> Enum.with_index()
    |> Enum.flat_map(fn {[left_id, left_x, left_y, left_updated_at], index} ->
      nodes
      |> Enum.drop(index + 1)
      |> Enum.flat_map(fn [right_id, right_x, right_y, right_updated_at] ->
        route_candidate(
          cycle_id,
          {left_id, left_x, left_y, left_updated_at},
          {right_id, right_x, right_y, right_updated_at},
          existing_pairs,
          degrees,
          route_history,
          origin_counts,
          preferred_pairs,
          newest_node_id
        )
      end)
    end)
  end

  defp route_candidate(
         cycle_id,
         {left_id, left_x, left_y, left_updated_at},
         {right_id, right_x, right_y, right_updated_at},
         existing_pairs,
         degrees,
         route_history,
         origin_counts,
         preferred_pairs,
         newest_node_id
       ) do
    distance = distance(left_x, left_y, right_x, right_y)
    key = pair(left_id, right_id)

    eligible? =
      distance <= @background_reach and not MapSet.member?(existing_pairs, key) and
        Map.get(degrees, left_id, 0) < @maximum_route_degree and
        Map.get(degrees, right_id, 0) < @maximum_route_degree

    if eligible? do
      history = Map.get(route_history, key, %{generation: 0, last_event_at: nil})
      seed = :erlang.phash2({cycle_id, key, :route, history.generation}, 2_147_483_647)

      changed_at_ms =
        max(
          max(timestamp_ms(left_updated_at), timestamp_ms(right_updated_at)),
          timestamp_ms(history.last_event_at)
        )

      left_degree = Map.get(degrees, left_id, 0)
      right_degree = Map.get(degrees, right_id, 0)
      minimum_degree = min(left_degree, right_degree)
      maximum_degree = max(left_degree, right_degree)

      delay_ms =
        18_000 + round(distance * 180_000) + rem(seed, 75_001) + minimum_degree * 16_000

      left_origins = Map.get(origin_counts, left_id, 0)
      right_origins = Map.get(origin_counts, right_id, 0)

      arrival_response? =
        MapSet.member?(preferred_pairs, key) and newest_node_id in [left_id, right_id]

      {source_id, target_id, origin_count} =
        cond do
          arrival_response? and newest_node_id == left_id ->
            {right_id, left_id, left_origins}

          arrival_response? and newest_node_id == right_id ->
            {left_id, right_id, right_origins}

          left_origins < right_origins ->
            {right_id, left_id, left_origins}

          right_origins < left_origins ->
            {left_id, right_id, right_origins}

          rem(seed, 2) == 0 ->
            {right_id, left_id, left_origins}

          true ->
            {left_id, right_id, right_origins}
        end

      [
        %{
          source_id: source_id,
          target_id: target_id,
          distance: distance,
          seed: seed,
          due_at_ms: changed_at_ms + delay_ms,
          minimum_degree: minimum_degree,
          maximum_degree: maximum_degree,
          origin_count: origin_count,
          arrival_priority: if(arrival_response?, do: 0, else: 1),
          proximity_priority: if(MapSet.member?(preferred_pairs, key), do: 0, else: 1)
        }
      ]
    else
      []
    end
  end

  defp retirement_candidate(
         existing_routes,
         degrees,
         origin_counts,
         node_positions,
         preferred_pairs,
         now_ms
       ) do
    existing_routes
    |> Enum.flat_map(fn [id, source_id, target_id, seed, started_at, duration] ->
      can_retire? =
        Map.get(degrees, source_id, 0) > 1 and Map.get(degrees, target_id, 0) > 1 and
          not MapSet.member?(preferred_pairs, pair(source_id, target_id)) and
          alternate_path?(existing_routes, id, source_id, target_id)

      distance = route_distance(node_positions, source_id, target_id)
      proximity = max(0.0, 1.0 - distance / @background_reach)
      proximity_lifetime = round(proximity * 150_000)

      due_at_ms =
        timestamp_ms(started_at) + duration + 75_000 + proximity_lifetime + rem(seed, 120_001)

      if can_retire? and due_at_ms <= now_ms do
        [%{id: id, due_at_ms: due_at_ms, origin_count: Map.get(origin_counts, target_id, 0)}]
      else
        []
      end
    end)
    |> Enum.min_by(&{-&1.origin_count, &1.due_at_ms}, fn -> nil end)
  end

  defp nearest_pairs(nodes, count) do
    nodes
    |> Enum.flat_map(fn [node_id, x, y, _updated_at] ->
      nodes
      |> Enum.reject(fn [other_id | _rest] -> other_id == node_id end)
      |> Enum.map(fn [other_id, other_x, other_y, _other_updated_at] ->
        {distance(x, y, other_x, other_y), pair(node_id, other_id)}
      end)
      |> Enum.filter(fn {route_distance, _pair} -> route_distance <= @background_reach end)
      |> Enum.sort()
      |> Enum.take(count)
      |> Enum.map(&elem(&1, 1))
    end)
    |> MapSet.new()
  end

  defp route_distance(node_positions, source_id, target_id) do
    case {Map.get(node_positions, source_id), Map.get(node_positions, target_id)} do
      {{source_x, source_y}, {target_x, target_y}} ->
        distance(source_x, source_y, target_x, target_y)

      _missing ->
        @background_reach
    end
  end

  defp alternate_path?(routes, excluded_id, source_id, target_id) do
    adjacency =
      routes
      |> Enum.reject(fn [id | _rest] -> id == excluded_id end)
      |> Enum.reduce(%{}, fn [_id, left, right | _rest], acc ->
        acc
        |> Map.update(left, MapSet.new([right]), &MapSet.put(&1, right))
        |> Map.update(right, MapSet.new([left]), &MapSet.put(&1, left))
      end)

    reachable?(adjacency, [source_id], MapSet.new(), target_id)
  end

  defp reachable?(_adjacency, [], _visited, _target), do: false
  defp reachable?(_adjacency, [target | _rest], _visited, target), do: true

  defp reachable?(adjacency, [current | rest], visited, target) do
    if MapSet.member?(visited, current) do
      reachable?(adjacency, rest, visited, target)
    else
      neighbours = adjacency |> Map.get(current, MapSet.new()) |> MapSet.to_list()
      reachable?(adjacency, rest ++ neighbours, MapSet.put(visited, current), target)
    end
  end

  defp insert_route!(
         cycle_id,
         source_id,
         target_id,
         distance,
         seed,
         growth_started_at
       ) do
    insert_route!(cycle_id, source_id, target_id, distance, seed, growth_started_at, nil)
  end

  defp insert_route!(
         cycle_id,
         source_id,
         target_id,
         distance,
         seed,
         growth_started_at,
         duration_ms
       ) do
    seed = seed || :erlang.phash2({cycle_id, source_id, target_id}, 2_147_483_647)

    query!(
      "INSERT INTO connections (cycle_id, source_id, target_id, path_seed, state, growth_started_at, growth_duration_ms, algorithm_version) VALUES (?, ?, ?, ?, 'active', ?, ?, 4)",
      [
        cycle_id,
        source_id,
        target_id,
        seed,
        growth_started_at || now(),
        duration_ms || growth_duration_ms(distance, seed)
      ]
    )
  end

  # Hyphal growth is local and exploratory rather than a fixed nearest-neighbour
  # graph. The first plausible route is proximity-led. A second route favours a
  # different approach direction, while further routes are deterministic but
  # probabilistic-looking so dense placements do not all produce the same shape.
  defp local_candidates([], _cycle_id, _id), do: []

  defp local_candidates(
         [{nearest_distance, _nearest_id, nearest_angle} = nearest | rest],
         cycle_id,
         id
       ) do
    if nearest_distance > @maximum_local_radius do
      []
    else
      local_radius =
        nearest_distance
        |> Kernel.*(1.8)
        |> max(@minimum_local_radius)
        |> min(@maximum_local_radius)

      nearby =
        rest
        |> Enum.filter(fn {candidate_distance, _other_id, _angle} ->
          candidate_distance <= local_radius
        end)

      {support, remaining} = choose_directional_support(nearby, nearest_angle, local_radius)

      exploratory =
        remaining
        |> Enum.filter(fn {candidate_distance, other_id, angle} ->
          closeness = max(0.0, 1.0 - candidate_distance / local_radius)
          diversity = angular_separation(nearest_angle, angle) / :math.pi()
          likelihood = 0.12 + closeness * 0.43 + diversity * 0.2
          deterministic_fraction({cycle_id, id, other_id}) <= likelihood
        end)
        |> Enum.sort_by(fn {candidate_distance, _other_id, angle} ->
          candidate_distance / local_radius - angular_separation(nearest_angle, angle) * 0.08
        end)
        |> Enum.take(@max_direct_connections - 2)

      [nearest] ++ List.wrap(support) ++ exploratory
    end
  end

  defp choose_directional_support([], _nearest_angle, _local_radius), do: {nil, []}

  defp choose_directional_support(candidates, nearest_angle, local_radius) do
    support =
      Enum.max_by(candidates, fn {candidate_distance, _other_id, angle} ->
        diversity = angular_separation(nearest_angle, angle) / :math.pi()
        closeness = max(0.0, 1.0 - candidate_distance / local_radius)
        diversity * 0.68 + closeness * 0.32
      end)

    {support, List.delete(candidates, support)}
  end

  defp angular_separation(left, right) do
    difference = abs(left - right)
    min(difference, 2 * :math.pi() - difference)
  end

  defp deterministic_fraction(value),
    do: :erlang.phash2(value, 10_000) / 9_999

  defp pair(left, right) when left < right, do: {left, right}
  defp pair(left, right), do: {right, left}

  defp timestamp_ms(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, timestamp, _offset} -> DateTime.to_unix(timestamp, :millisecond)
      _ -> 0
    end
  end

  defp timestamp_ms(_value), do: 0

  defp timestamp(value), do: value |> DateTime.truncate(:millisecond) |> DateTime.to_iso8601()

  defp growth_delay_ms(0, _distance, seed), do: rem(seed, 450)

  defp growth_delay_ms(index, distance, seed),
    do: round(700 + index * 850 + distance * 4_500 + rem(seed, 1_100))

  defp growth_duration_ms(distance, seed),
    do: round(@growth_duration_ms - 2_000 + distance * 12_000 + rem(seed, 4_001))

  defp ensure_schema! do
    query!(
      "CREATE TABLE IF NOT EXISTS cycles (id INTEGER PRIMARY KEY AUTOINCREMENT, status TEXT NOT NULL, started_at TEXT NOT NULL, ended_at TEXT)"
    )

    query!(
      "CREATE TABLE IF NOT EXISTS contributions (id INTEGER PRIMARY KEY AUTOINCREMENT, cycle_id INTEGER NOT NULL, title TEXT, color TEXT NOT NULL, size REAL NOT NULL, x REAL, y REAL, state TEXT NOT NULL, source TEXT NOT NULL, inserted_at TEXT NOT NULL, updated_at TEXT NOT NULL)"
    )

    query!(
      "CREATE TABLE IF NOT EXISTS connections (id INTEGER PRIMARY KEY AUTOINCREMENT, cycle_id INTEGER NOT NULL, source_id INTEGER NOT NULL, target_id INTEGER NOT NULL, path_seed INTEGER NOT NULL, state TEXT NOT NULL, growth_started_at TEXT NOT NULL, growth_duration_ms INTEGER NOT NULL, algorithm_version INTEGER NOT NULL DEFAULT 2, retired_at TEXT)"
    )

    connection_columns = query!("PRAGMA table_info(connections)").rows

    unless Enum.any?(connection_columns, fn [_cid, name | _rest] ->
             name == "algorithm_version"
           end) do
      query!("ALTER TABLE connections ADD COLUMN algorithm_version INTEGER NOT NULL DEFAULT 1")
    end

    unless Enum.any?(connection_columns, fn [_cid, name | _rest] -> name == "retired_at" end) do
      query!("ALTER TABLE connections ADD COLUMN retired_at TEXT")
    end

    query!("CREATE INDEX IF NOT EXISTS contributions_cycle_idx ON contributions(cycle_id, state)")
    query!("CREATE INDEX IF NOT EXISTS connections_cycle_idx ON connections(cycle_id, state)")
    current_cycle_id!()
  end

  defp current_cycle_id! do
    case query!("SELECT id FROM cycles WHERE status = 'active' ORDER BY id DESC LIMIT 1").rows do
      [[id]] -> id
      [] -> create_cycle!()
    end
  end

  defp create_cycle! do
    query!("INSERT INTO cycles (status, started_at) VALUES ('active', ?)", [now()])
    query!("SELECT last_insert_rowid()").rows |> hd() |> hd()
  end

  defp contribution([id, title, color, size, x, y, state, source, inserted_at, updated_at]),
    do: %{
      id: id,
      title: title,
      color: color,
      size: size,
      x: x,
      y: y,
      state: state,
      source: source,
      inserted_at: inserted_at,
      updated_at: updated_at
    }

  defp connection([id, source_id, target_id, seed, started_at, duration, algorithm_version]),
    do: %{
      id: id,
      source_id: source_id,
      target_id: target_id,
      path_seed: seed,
      growth_started_at: started_at,
      growth_duration_ms: duration,
      algorithm_version: algorithm_version
    }

  defp normalize_title(value) when is_binary(value),
    do: value |> String.trim() |> String.slice(0, 80)

  defp normalize_title(_), do: ""
  defp normalize_color("#" <> hex = color) when byte_size(hex) == 6, do: color
  defp normalize_color(_), do: "#d8e7b0"

  defp normalize_size(value) do
    case Float.parse(to_string(value || "")) do
      {size, _} -> min(1.5, max(0.5, size))
      _ -> 1.0
    end
  end

  defp clamp_coordinate(value) when is_number(value), do: min(1.0, max(0.0, value / 1))
  defp distance(x1, y1, x2, y2), do: :math.sqrt(:math.pow(x1 - x2, 2) + :math.pow(y1 - y2, 2))

  defp now(offset_ms \\ 0) do
    DateTime.utc_now()
    |> DateTime.add(offset_ms, :millisecond)
    |> DateTime.truncate(:millisecond)
    |> DateTime.to_iso8601()
  end

  defp with_write_repo(database_path, fun) do
    :global.trans({{__MODULE__, Path.expand(database_path)}, self()}, fn ->
      with_repo(database_path, fun)
    end)
  end

  defp with_repo(database_path, fun),
    do:
      with_raw_repo(database_path, fn ->
        ensure_schema!()
        fun.()
      end)

  defp with_raw_repo(database_path, fun) do
    File.mkdir_p!(Path.dirname(database_path))

    {:ok, repo} =
      Repo.start_link(
        database: database_path,
        pool_size: 1,
        name: nil,
        journal_mode: :wal,
        busy_timeout: 10_000
      )

    previous = Repo.put_dynamic_repo(repo)

    try do
      fun.()
    after
      Repo.put_dynamic_repo(previous)
      GenServer.stop(repo)
    end
  end

  defp query!(sql, params \\ []),
    do: Ecto.Adapters.SQL.query!(Repo.get_dynamic_repo(), sql, params)

  defp scalar!(sql, params \\ []), do: query!(sql, params).rows |> hd() |> hd()

  defp live_database_bytes! do
    page_count = scalar!("PRAGMA page_count")
    free_pages = scalar!("PRAGMA freelist_count")
    page_size = scalar!("PRAGMA page_size")
    max(0, page_count - free_pages) * page_size
  end
end

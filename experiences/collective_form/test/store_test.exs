defmodule WakeCanvas.Experience.CollectiveForm.StoreTest do
  use ExUnit.Case

  alias WakeCanvas.Experience.CollectiveForm.Store

  setup do
    nonce = Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)

    path =
      Path.join(System.tmp_dir!(), "collective-form-#{nonce}.sqlite")

    on_exit(fn -> Enum.each([path, path <> "-shm", path <> "-wal"], &File.rm/1) end)
    %{path: path}
  end

  test "persists contributions, positions, and deterministic connections", %{path: path} do
    assert :ok = Store.migrate(path)

    assert :ok =
             Store.add_contribution(path, %{
               "title" => "Seed",
               "color" => "#aabbcc",
               "size" => "1.0"
             })

    assert :ok =
             Store.add_contribution(path, %{
               "title" => "Neighbour",
               "color" => "#ddeeff",
               "size" => "0.7"
             })

    assert %{contributions: [first, second], connections: []} = Store.snapshot(path)
    assert :ok = Store.place_contribution(path, first.id, 0.25, 0.5)
    assert :ok = Store.place_contribution(path, second.id, 0.65, 0.5)

    assert %{contributions: contributions, connections: [connection]} = Store.snapshot(path)
    assert Enum.all?(contributions, &(&1.state == "placed"))
    assert connection.source_id == second.id
    assert connection.target_id == first.id

    seed = connection.path_seed
    assert :ok = Store.migrate(path)
    assert %{connections: [%{path_seed: ^seed}]} = Store.snapshot(path)
  end

  test "moving a contribution only replaces its affected connections", %{path: path} do
    for title <- ["One", "Two", "Three"] do
      assert :ok = Store.add_contribution(path, %{"title" => title})
    end

    [one, two, three] = Store.snapshot(path).contributions
    Store.place_contribution(path, one.id, 0.2, 0.5)
    Store.place_contribution(path, two.id, 0.5, 0.5)
    Store.place_contribution(path, three.id, 0.8, 0.5)
    before = Store.snapshot(path)

    assert :ok = Store.place_contribution(path, three.id, 0.75, 0.2)
    after_move = Store.snapshot(path)
    assert length(after_move.connections) == length(before.connections)

    assert Enum.all?(
             after_move.connections,
             &(&1.source_id == three.id or &1.target_id == three.id or
                 Enum.any?(before.connections, fn previous -> previous.id == &1.id end))
           )
  end

  test "returning a contribution to the tray preserves it for later placement", %{path: path} do
    for title <- ["One", "Two"] do
      assert :ok = Store.add_contribution(path, %{"title" => title})
    end

    [one, two] = Store.snapshot(path).contributions
    assert :ok = Store.place_contribution(path, one.id, 0.3, 0.5)
    assert :ok = Store.place_contribution(path, two.id, 0.6, 0.5)
    assert [_connection] = Store.snapshot(path).connections

    assert :ok = Store.unplace_contribution(path, two.id)
    snapshot = Store.snapshot(path)
    returned = Enum.find(snapshot.contributions, &(&1.id == two.id))
    assert %{state: "unplaced", x: nil, y: nil} = returned
    assert snapshot.connections == []

    assert :ok = Store.place_contribution(path, two.id, 0.7, 0.4)
    replaced = Store.snapshot(path)
    assert Enum.find(replaced.contributions, &(&1.id == two.id)).state == "placed"
    assert length(replaced.connections) == 1
  end

  test "a contribution placed in a cluster connects to several nearby contributions", %{
    path: path
  } do
    for title <- ["One", "Two", "Three", "New"] do
      assert :ok = Store.add_contribution(path, %{"title" => title})
    end

    [one, two, three, new] = Store.snapshot(path).contributions
    Store.place_contribution(path, one.id, 0.35, 0.5)
    Store.place_contribution(path, two.id, 0.5, 0.35)
    Store.place_contribution(path, three.id, 0.65, 0.5)
    Store.place_contribution(path, new.id, 0.5, 0.5)

    arrival_connections =
      Store.snapshot(path).connections
      |> Enum.filter(&(&1.source_id == new.id or &1.target_id == new.id))

    assert length(arrival_connections) in 2..3

    assert Enum.all?(arrival_connections, fn connection ->
             other_id =
               if connection.source_id == new.id,
                 do: connection.target_id,
                 else: connection.source_id

             other_id in [one.id, two.id, three.id]
           end)

    assert Enum.any?(arrival_connections, &(&1.source_id == new.id))
    assert Enum.any?(arrival_connections, &(&1.target_id == new.id))

    assert Enum.uniq(Enum.map(arrival_connections, & &1.growth_duration_ms)) ==
             Enum.map(arrival_connections, & &1.growth_duration_ms)
  end

  test "a contribution beyond the local growth radius remains unconnected", %{path: path} do
    for title <- ["Seed", "Remote"] do
      assert :ok = Store.add_contribution(path, %{"title" => title})
    end

    [seed, remote] = Store.snapshot(path).contributions
    Store.place_contribution(path, seed.id, 0.05, 0.05)
    Store.place_contribution(path, remote.id, 0.95, 0.95)

    assert Store.snapshot(path).connections == []
  end

  test "network evolution persists an ordinary route between existing contributions", %{
    path: path
  } do
    for title <- ["One", "Two", "Three", "Four"] do
      assert :ok = Store.add_contribution(path, %{"title" => title})
    end

    [one, two, three, four] = Store.snapshot(path).contributions
    Store.place_contribution(path, one.id, 0.2, 0.5)
    Store.place_contribution(path, two.id, 0.4, 0.5)
    Store.place_contribution(path, three.id, 0.6, 0.5)
    Store.place_contribution(path, four.id, 0.8, 0.5)

    before = Store.snapshot(path)
    future = DateTime.add(DateTime.utc_now(), 30, :minute)

    assert :changed = Store.evolve(path, future)

    after_evolution = Store.snapshot(path)
    assert length(after_evolution.connections) == length(before.connections) + 1
    assert Enum.any?(after_evolution.connections, &(&1.algorithm_version == 4))

    previous_ids = MapSet.new(before.connections, & &1.id)
    added_route = Enum.find(after_evolution.connections, &(!MapSet.member?(previous_ids, &1.id)))

    assert MapSet.new([added_route.source_id, added_route.target_id]) ==
             MapSet.new([two.id, four.id])

    assert added_route.target_id == four.id

    assert after_evolution == Store.snapshot(path)
  end

  test "mature redundant routes retire and later regrow with a new path", %{path: path} do
    for title <- ["One", "Two", "Three", "Four"] do
      assert :ok = Store.add_contribution(path, %{"title" => title})
    end

    [one, two, three, four] = Store.snapshot(path).contributions
    Store.place_contribution(path, one.id, 0.2, 0.5)
    Store.place_contribution(path, two.id, 0.4, 0.5)
    Store.place_contribution(path, three.id, 0.6, 0.5)
    Store.place_contribution(path, four.id, 0.8, 0.5)

    original = Store.snapshot(path)
    assert length(original.connections) == 3

    future = DateTime.add(DateTime.utc_now(), 30, :minute)
    assert Enum.all?(1..3, fn _index -> Store.evolve(path, future) == :changed end)
    saturated = Store.snapshot(path)
    assert length(saturated.connections) == 6

    assert :changed = Store.evolve(path, DateTime.add(future, 30, :minute))
    after_retirement = Store.snapshot(path)
    assert length(after_retirement.connections) == 5

    degrees =
      Enum.reduce(after_retirement.connections, %{}, fn route, acc ->
        acc
        |> Map.update(route.source_id, 1, &(&1 + 1))
        |> Map.update(route.target_id, 1, &(&1 + 1))
      end)

    assert Enum.all?([one.id, two.id, three.id, four.id], &(Map.get(degrees, &1, 0) >= 1))

    assert :changed = Store.evolve(path, DateTime.add(future, 60, :minute))
    regrown = Store.snapshot(path)
    assert length(regrown.connections) == 6

    saturated_seeds = MapSet.new(saturated.connections, & &1.path_seed)
    assert Enum.any?(regrown.connections, &(!MapSet.member?(saturated_seeds, &1.path_seed)))
  end

  test "new cycle keeps prior data archived and starts empty", %{path: path} do
    Store.add_contribution(path, %{"title" => "Old"})
    old_cycle = Store.snapshot(path).cycle_id
    assert :ok = Store.reset_cycle(path)
    assert %{cycle_id: new_cycle, contributions: [], connections: []} = Store.snapshot(path)
    assert new_cycle != old_cycle
  end
end

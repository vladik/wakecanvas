defmodule WakeCanvas.Experience.CollectiveForm.PareidoliaTest do
  use ExUnit.Case, async: true

  alias WakeCanvas.Experience.CollectiveForm.Pareidolia

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "collective-form-pareidolia-#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf!(directory) end)
    %{directory: directory}
  end

  test "prepares bounded candidates and validates a matching response", %{directory: directory} do
    assert {:ok, prepared} = Pareidolia.prepare(directory, snapshot())
    assert prepared.candidate_count > 0
    assert prepared.candidate_count <= 16

    request_path = Path.join([directory, "pareidolia", "request.json"])
    sheet_path = Path.join([directory, "pareidolia", "candidate-sheet.svg"])
    response_path = Path.join([directory, "pareidolia", "response.json"])

    assert File.exists?(request_path)
    assert File.exists?(sheet_path)
    assert {:ok, _replacement} = Pareidolia.prepare(directory, snapshot())
    request = request_path |> File.read!() |> Jason.decode!()
    candidate = hd(request["candidates"])

    response = %{
      analysis_id: request["analysis_id"],
      network_fingerprint: request["network_fingerprint"],
      interpretations: [
        %{
          candidate_id: candidate["id"],
          title: "A bird in flight",
          confidence: 0.82,
          contours: [
            %{closed: true, points: [[0.2, 0.4], [0.5, 0.2], [0.8, 0.4], [0.5, 0.6]]}
          ]
        }
      ]
    }

    File.write!(response_path, Jason.encode!(response))
    status = Pareidolia.status(directory)
    assert status.status == "ready"

    assert [
             %{
               title: "A bird in flight",
               connectionIds: ids,
               contours: [%{closed: true, points: points}]
             }
           ] = status.interpretations

    assert ids == candidate["connection_ids"]
    assert length(points) == 4
    assert length(status.network["connections"]) == 6
  end

  test "uses the whole graph and scales candidate count for a large network" do
    snapshot = large_snapshot()
    candidates = Pareidolia.candidates(snapshot)
    selected_connection_ids = candidates |> Enum.flat_map(& &1.connection_ids) |> MapSet.new()

    selected_node_ids =
      snapshot.connections
      |> Enum.filter(&MapSet.member?(selected_connection_ids, &1.id))
      |> Enum.flat_map(&[&1.source_id, &1.target_id])
      |> MapSet.new()

    assert length(candidates) > 16
    assert length(candidates) <= 48
    assert MapSet.member?(selected_node_ids, 1)
    assert MapSet.member?(selected_node_ids, 30)
  end

  test "rejects a response for another network", %{directory: directory} do
    assert {:ok, _prepared} = Pareidolia.prepare(directory, snapshot())

    request =
      Path.join([directory, "pareidolia", "request.json"]) |> File.read!() |> Jason.decode!()

    response = %{
      analysis_id: request["analysis_id"],
      network_fingerprint: "stale",
      interpretations: [%{candidate_id: 1, title: "Shape", confidence: 0.7}]
    }

    Path.join([directory, "pareidolia", "response.json"])
    |> File.write!(Jason.encode!(response))

    assert %{status: "invalid", error: "fingerprint_mismatch"} = Pareidolia.status(directory)
  end

  defp snapshot do
    contributions =
      [
        {1, 0.15, 0.5},
        {2, 0.3, 0.25},
        {3, 0.5, 0.18},
        {4, 0.7, 0.3},
        {5, 0.82, 0.55},
        {6, 0.52, 0.72}
      ]
      |> Enum.map(fn {id, x, y} ->
        %{id: id, x: x, y: y, state: "placed", color: "#d8e7b0", size: 1.0}
      end)

    connections =
      [{1, 2}, {2, 3}, {3, 4}, {4, 5}, {5, 6}, {6, 1}]
      |> Enum.with_index(1)
      |> Enum.map(fn {{source, target}, id} ->
        %{id: id, source_id: source, target_id: target, path_seed: id * 137}
      end)

    %{cycle_id: 9, contributions: contributions, connections: connections}
  end

  defp large_snapshot do
    contributions =
      for row <- 0..4, column <- 0..5 do
        id = row * 6 + column + 1

        %{
          id: id,
          x: (column + 0.5) / 6,
          y: (row + 0.5) / 5,
          state: "placed",
          color: "#d8e7b0",
          size: 1.0
        }
      end

    pairs =
      for row <- 0..4, column <- 0..4 do
        left = row * 6 + column + 1
        {left, left + 1}
      end ++
        for row <- 0..3, column <- 0..5 do
          top = row * 6 + column + 1
          {top, top + 6}
        end

    connections =
      pairs
      |> Enum.with_index(1)
      |> Enum.map(fn {{source, target}, id} ->
        %{id: id, source_id: source, target_id: target, path_seed: id * 173}
      end)

    %{cycle_id: 10, contributions: contributions, connections: connections}
  end
end

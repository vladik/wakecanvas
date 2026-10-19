defmodule WakeCanvas.Access.AttemptLimiter do
  @moduledoc false
  use GenServer

  @window_ms 60_000
  @max_failures 5

  def start_link(options),
    do: GenServer.start_link(__MODULE__, %{}, Keyword.put_new(options, :name, __MODULE__))

  def check(key), do: GenServer.call(__MODULE__, {:check, key})
  def failure(key), do: GenServer.cast(__MODULE__, {:failure, key})
  def success(key), do: GenServer.cast(__MODULE__, {:success, key})

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:check, key}, _from, state) do
    now = System.monotonic_time(:millisecond)
    recent = recent_failures(Map.get(state, key, []), now)
    state = put_or_delete(state, key, recent)

    reply =
      if length(recent) >= @max_failures,
        do: {:error, max(1, div(@window_ms - (now - List.last(recent)), 1_000))},
        else: :ok

    {:reply, reply, state}
  end

  @impl true
  def handle_cast({:failure, key}, state) do
    now = System.monotonic_time(:millisecond)
    failures = recent_failures(Map.get(state, key, []), now) ++ [now]
    {:noreply, Map.put(state, key, failures)}
  end

  def handle_cast({:success, key}, state), do: {:noreply, Map.delete(state, key)}

  defp recent_failures(failures, now), do: Enum.filter(failures, &(now - &1 < @window_ms))

  defp put_or_delete(state, key, []), do: Map.delete(state, key)
  defp put_or_delete(state, key, failures), do: Map.put(state, key, failures)
end

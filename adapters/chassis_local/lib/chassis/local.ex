defmodule Chassis.Adapter.Local do
  @moduledoc """
  Local-process adapter: spawns a real OS process via `Port.open/2`,
  monitors it through the port's `:exit_status` message, and reports
  health based on whether the port is still open.

  Implements `Chassis.Contracts.Adapter`.
  """
  @behaviour Chassis.Contracts.Adapter

  @impl true
  @spec prepare(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def prepare(payload, _opts) do
    {:ok, Map.put(payload, :prepared, true)}
  end

  @impl true
  @spec start(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def start(payload, opts) do
    command = Keyword.get(opts, :command, "/bin/true")
    args = Keyword.get(opts, :args, [])
    exe = System.find_executable(command) || command

    if File.exists?(exe) do
      port =
        Port.open({:spawn_executable, exe}, [
          :binary,
          :exit_status,
          {:args, args}
        ])

      {:ok, Map.merge(payload, %{port: port, exe: exe, status: :started})}
    else
      {:error, {:executable_not_found, command}}
    end
  rescue
    e -> {:error, {:port_open_failed, Exception.message(e)}}
  end

  @impl true
  @spec stop(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def stop(%{port: port} = payload, _opts) when is_port(port) do
    if Port.info(port) do
      Port.close(port)
    end

    {:ok, %{payload | status: :stopped}}
  end

  def stop(payload, _opts), do: {:ok, Map.put(payload, :status, :stopped)}

  @impl true
  @spec health(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def health(%{port: port} = payload, _opts) when is_port(port) do
    if Port.info(port) do
      {:ok, Map.put(payload, :status, :healthy)}
    else
      {:ok, Map.put(payload, :status, :exited)}
    end
  end

  def health(payload, _opts), do: {:ok, Map.put(payload, :status, :unknown)}

  @doc """
  Synchronous variant: starts a port, waits for its exit, returns the exit
  status. Useful for short-lived processes (e.g. dev smoke).
  """
  @spec run_sync(String.t(), [String.t()], non_neg_integer()) ::
          {:ok, integer()} | {:error, term()}
  def run_sync(command, args \\ [], timeout_ms \\ 5_000) do
    case start(%{command: command}, command: command, args: args) do
      {:ok, %{port: port}} -> await_exit(port, timeout_ms)
      err -> err
    end
  end

  defp await_exit(port, timeout_ms) do
    receive do
      {^port, {:exit_status, status}} -> {:ok, status}
    after
      timeout_ms ->
        if Port.info(port), do: Port.close(port)
        {:error, :timeout}
    end
  end
end

defmodule Chassis.Local do
  @moduledoc "Compatibility facade."
end

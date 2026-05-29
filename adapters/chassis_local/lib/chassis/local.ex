defmodule Chassis.Adapter.Local do
  @moduledoc "Local process adapter using Port.open/2."
  def prepare(payload, _opts \\ []), do: {:ok, Map.put(payload, :prepared, true)}

  def start(payload, opts \\ []) do
    command = Keyword.get(opts, :command, "true")

    port =
      Port.open({:spawn_executable, System.find_executable(command) || "/bin/true"}, [
        :binary,
        :exit_status
      ])

    {:ok, Map.merge(payload, %{port: port, status: :started})}
  end

  def stop(payload, _opts \\ []), do: {:ok, Map.put(payload, :status, :stopped)}
  def health(payload, _opts \\ []), do: {:ok, Map.put(payload, :status, :healthy)}
end

defmodule Chassis.Local do
  @moduledoc "Compatibility facade."
end

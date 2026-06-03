defmodule Chassis.CLI.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    if System.get_env("__BURRITO") do
      run_burrito_cli()
    else
      Supervisor.start_link([], strategy: :one_for_one, name: Chassis.CLI.Supervisor)
    end
  end

  defp run_burrito_cli do
    argv = :init.get_plain_arguments() |> Enum.map(&to_string/1)
    {code, payload} = Chassis.CLI.dispatch(argv)
    IO.write(Chassis.CLI.Encoding.encode(payload, json?: "--json" in argv) <> "\n")
    System.halt(code)
  end
end

defmodule Chassis.CLI.Runtime do
  @moduledoc "Shared in-memory runtime state used by CLI command modules."

  @registry __MODULE__.AppRegistry
  @receipts_store __MODULE__.ReceiptsStore
  @fence_store __MODULE__.FenceStore
  @checkpoint_store __MODULE__.CheckpointStore
  @outbox __MODULE__.Outbox

  @spec registry() :: atom()
  def registry, do: ensure_started(@registry, Chassis.AppRegistry)

  @spec receipts_store() :: atom()
  def receipts_store, do: ensure_started(@receipts_store, Chassis.Receipts.Store.Memory)

  @spec fence_store() :: atom()
  def fence_store, do: ensure_started(@fence_store, Chassis.StackManager.FenceStore)

  @spec checkpoint_store() :: atom()
  def checkpoint_store,
    do: ensure_started(@checkpoint_store, Chassis.StackManager.CheckpointStore)

  @spec outbox() :: atom()
  def outbox, do: ensure_started(@outbox, Chassis.Mezzanine.Bridge.Outbox)

  @spec reset!() :: :ok
  def reset! do
    for name <- [@registry, @receipts_store, @fence_store, @checkpoint_store, @outbox] do
      case Process.whereis(name) do
        nil ->
          :ok

        pid ->
          Process.exit(pid, :kill)
          wait_down(name)
      end
    end

    :ok
  end

  defp ensure_started(name, module) do
    case Process.whereis(name) do
      nil ->
        case module.start_link(name: name) do
          {:ok, _pid} -> name
          {:error, {:already_started, _pid}} -> name
        end

      _pid ->
        name
    end
  end

  defp wait_down(name) do
    if Process.whereis(name) do
      Process.sleep(5)
      wait_down(name)
    else
      :ok
    end
  end
end

defmodule Chassis.CLI.PlaintextVaultBackend do
  @moduledoc """
  Test/dev vault backend for CLI key-command dispatch tests.

  It is enabled only by the explicit `--plaintext-vault` switch. The default
  key path still uses `Chassis.Secrets.Materializer.Sops`.
  """

  @spec decrypt(Path.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def decrypt(path, _opts) do
    case File.read(path) do
      {:ok, body} ->
        Jason.decode(body)

      {:error, :enoent} ->
        {:ok, %{}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec encrypt(Path.t(), map(), keyword()) :: :ok | {:error, term()}
  def encrypt(path, decoded, _opts) do
    with :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, body} <- Jason.encode(decoded) do
      File.write(path, body)
    end
  end
end

defmodule NSHKR.Observability.Emitter do
  @moduledoc "Local observability emitter behaviour."
  @callback emit_metric(map()) :: :ok | {:error, term()}
  @callback emit_health_signal(map()) :: :ok | {:error, term()}
end

defmodule Chassis.Metrics do
  @moduledoc "OTel-compatible metrics bridge."
  @behaviour NSHKR.Observability.Emitter
  @metric_names ~w(chassis_deployment_count_total chassis_provisioning_step_count_total chassis_ssh_session_duration_ms chassis_mesh_node_count chassis_mesh_health_failures_total chassis_evolution_run_count_total chassis_model_materialization_count_total chassis_hardware_admission_count_total chassis_tensor_reload_count_total chassis_swap_count_total chassis_probe_count_total chassis_rollback_count_total)
  @impl true
  def emit_metric(metric),
    do: Chassis.Metrics.Backend.Test.put(Map.put_new(metric, :emitted_at, DateTime.utc_now()))

  @impl true
  def emit_health_signal(signal),
    do: Chassis.Metrics.Backend.Test.put(Map.put(signal, :kind, :health_signal))

  @spec metric_names() :: [String.t()]
  def metric_names, do: @metric_names
end

for backend <- [OTel, Console, File, Test] do
  defmodule Module.concat(Chassis.Metrics.Backend, backend) do
    @moduledoc "Metrics backend."
    @table :chassis_metrics_test
    def put(metric) do
      if __MODULE__ == Chassis.Metrics.Backend.Test do
        ensure_table()
        :ets.insert(@table, {System.unique_integer([:positive]), metric})
      end

      :ok
    end

    def list do
      ensure_table()
      @table |> :ets.tab2list() |> Enum.map(fn {_key, metric} -> metric end)
    end

    defp ensure_table do
      case :ets.info(@table) do
        :undefined -> :ets.new(@table, [:named_table, :public])
        _info -> @table
      end
    end
  end
end

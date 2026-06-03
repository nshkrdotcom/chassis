defmodule Chassis.CLI.Command.Model.Materialize do
  @moduledoc "Root CLI command for Phase 38 model weight materialization."

  alias Chassis.Model.Manifest
  alias Chassis.Model.WeightMaterializer

  @spec run([String.t()], map()) :: {:ok, map()} | {:error, term()}
  def run(positional, switches) do
    model_ref = Map.get(switches, :model) || Enum.at(positional, 0)

    target_host_ref =
      Map.get(switches, :target) || Map.get(switches, :host) || Enum.at(positional, 1)

    cond do
      is_nil(model_ref) ->
        {:error, %{reason: "missing --model"}}

      is_nil(target_host_ref) ->
        {:error, %{reason: "missing --target"}}

      true ->
        request = %{
          tenant_ref: Map.get(switches, :tenant, "tenant:dev"),
          installation_ref: Map.get(switches, :installation, "installation:dev"),
          model_ref: model_ref,
          target_host_ref: target_host_ref,
          source_strategy: :hf_hub,
          expected_digest_ref: Manifest.fixture_digest(model_ref),
          bandwidth_class: :bulk,
          verify_sha256?: Map.get(switches, :verify_sha256, false),
          dry_run?: Map.get(switches, :dry_run, false)
        }

        with {:ok, report} <- WeightMaterializer.materialize(request) do
          {:ok, WeightMaterializer.jsonable(report)}
        end
    end
  end
end

defmodule Chassis.CLI.Command.Model.CacheList do
  @moduledoc "Root CLI command for Phase 39 model cache listing."

  alias Chassis.Model.Cache

  @spec run([String.t()], map()) :: {:ok, map()} | {:error, term()}
  def run(positional, switches) do
    host_ref = Map.get(switches, :host) || Enum.at(positional, 0)

    if is_nil(host_ref) do
      {:error, %{reason: "missing --host"}}
    else
      with {:ok, report} <- Cache.list(host_ref, tenant_ref: Map.get(switches, :tenant)) do
        {:ok, Cache.jsonable(report)}
      end
    end
  end
end

defmodule Chassis.CLI.Command.Model.Fixture do
  @moduledoc "Root CLI command for Phase 41 model asset conformance fixtures."

  alias Chassis.ModelAsset.Conformance
  alias Chassis.ModelAsset.Conformance.Evidence

  @spec run([String.t()], map()) :: {:ok, map()} | {:error, term()}
  def run(positional, switches) do
    scenario = Map.get(switches, :scenario) || Enum.at(positional, 0)

    if is_nil(scenario) do
      {:error, %{reason: "missing --scenario"}}
    else
      with {:ok, report} <- Conformance.run(scenario) do
        {:ok, Evidence.jsonable(report)}
      end
    end
  end
end

defmodule Mix.Tasks.Chassis.Node.Trial do
  @moduledoc "Provision a local Chassis trial worker."
  use Mix.Task

  @shortdoc "Provision a Chassis trial worker"

  @impl Mix.Task
  def run(args) do
    {opts, _argv, _invalid} =
      OptionParser.parse(args,
        strict: [candidate_ref: :string, diff_path: :string, kind: :string, json: :boolean]
      )

    kind =
      case Keyword.get(opts, :kind, "fixture") do
        "fixture" -> :fixture
        "container" -> :container
        "systemd" -> :systemd
        "ssh" -> :ssh
        other -> Mix.raise("unknown trial kind: #{other}")
      end

    attrs = %{
      candidate_ref: Keyword.get(opts, :candidate_ref, "cand:dev:smoke"),
      diff_path: Keyword.get(opts, :diff_path, "test/fixtures/empty.patch")
    }

    case Chassis.Trial.Runtime.provision(attrs, kind: kind, approved_state_volume_mounts: []) do
      {:ok, trial} ->
        item = Chassis.Trial.Runtime.jsonable_trial(trial)

        if Keyword.get(opts, :json, false) do
          Mix.shell().info(Jason.encode!(item))
        else
          Mix.shell().info("#{item.trial_ref} #{item.provider}")
        end

      {:error, reason} ->
        Mix.raise("trial provisioning failed: #{inspect(reason)}")
    end
  end
end

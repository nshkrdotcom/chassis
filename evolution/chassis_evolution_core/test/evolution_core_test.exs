defmodule Chassis.Evolution.CoreTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Chassis.Evolution.Core
  alias Chassis.Evolution.Core.{ReceiptLog, Transitions}
  alias Chassis.Evolution.PromotionPreconditions

  test "every declared transition is legal and writes a transition receipt" do
    {:ok, log} = ReceiptLog.start_link(name: nil)

    for {from, allowed} <- Transitions.table(), to <- allowed do
      {:ok, core} =
        Core.start_link(
          name: nil,
          state: from,
          evolution_run_ref: "evo:#{from}:#{to}",
          receipt_log: log
        )

      metadata = if to == :promotion_requested, do: preconditions(), else: %{}
      assert {:ok, ^to} = Core.transition(core, to, metadata)
      assert Core.state(core) == to
    end

    receipts = ReceiptLog.list(log)
    assert Enum.any?(receipts, &(&1.from_state == :queued and &1.to_state == :failed))
    assert Enum.any?(receipts, &(&1.to_state == :promotion_requested))
  end

  test "illegal transitions are rejected and leave state unchanged" do
    {:ok, core} = Core.start_link(name: nil, state: :queued)

    assert {:error, {:illegal_transition, :queued, :promoting}} =
             Core.transition(core, :promoting)

    assert Core.state(core) == :queued

    for terminal <- [:committed, :rolled_back, :failed, :stopped] do
      {:ok, terminal_core} = Core.start_link(name: nil, state: terminal)

      assert {:error, {:illegal_transition, ^terminal, :queued}} =
               Core.transition(terminal_core, :queued)

      assert Core.state(terminal_core) == terminal
    end
  end

  test "promotion_requested requires every promotion precondition" do
    {:ok, core} = Core.start_link(name: nil, state: :awaiting_operator_consent)

    assert Core.transition(core, :promotion_requested, %{}) == {:error, :missing_field}
    assert Core.state(core) == :awaiting_operator_consent

    assert {:ok, :promotion_requested} =
             Core.transition(core, :promotion_requested, preconditions())
  end

  test "precondition_check returns missing_field for absent fields and blocks failed gates" do
    assert Core.precondition_check(%{}) == {:error, :missing_field}

    blocked =
      preconditions()
      |> Map.put(:regression_gate, :blocked)

    assert Core.precondition_check(blocked) == {:error, :regression_gate_blocked}
    assert Core.precondition_check(preconditions()) == :ok
  end

  test "crash recovery rehydrates the latest state from receipts" do
    {:ok, log} = ReceiptLog.start_link(name: nil)

    {:ok, first} =
      Core.start_link(name: nil, evolution_run_ref: "evo:recover", receipt_log: log)

    assert {:ok, :evidence_curated} = Core.transition(first, :evidence_curated)
    assert {:ok, :planning} = Core.transition(first, :planning)

    ref = Process.monitor(first)
    Process.unlink(first)
    Process.exit(first, :kill)
    assert_receive {:DOWN, ^ref, :process, ^first, :killed}, 1_000

    {:ok, recovered} =
      Core.start_link(name: nil, evolution_run_ref: "evo:recover", receipt_log: log)

    assert Core.state(recovered) == :planning
  end

  test "registry lists active evolution runs" do
    {:ok, registry} = Chassis.Evolution.Registry.start_link(name: nil)

    {:ok, _core} =
      Core.start_link(
        name: nil,
        evolution_run_ref: "evo:registry",
        failure_batch_ref: "fb:dev:smoke",
        registry: registry
      )

    assert [%{evolution_run_ref: "evo:registry", state: :queued}] =
             Chassis.Evolution.Registry.list(registry)
  end

  test "package-local start task emits structural JSON state" do
    Mix.Task.reenable("chassis.evolution.start")

    output =
      capture_io(fn ->
        Mix.Tasks.Chassis.Evolution.Start.run([
          "--batch-ref",
          "fb:dev:smoke",
          "--json"
        ])
      end)

    assert {:ok, decoded} = Jason.decode(output)
    assert decoded["failure_batch_ref"] == "fb:dev:smoke"
    assert decoded["state"] == "queued"
  end

  defp preconditions do
    Map.new(PromotionPreconditions.required_fields(), fn
      :regression_gate -> {:regression_gate, :passed}
      :approved_state_volume_mounts -> {:approved_state_volume_mounts, []}
      field -> {field, "#{field}:dev:smoke"}
    end)
  end
end

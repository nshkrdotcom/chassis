defmodule Chassis.DoctorTest do
  @moduledoc """
  Phase 7 — `chassis_doctor` diagnostics tests.

  Doctor must run named checks, return per-check pass/fail, and aggregate
  to an overall status. Tests inject failing checks via a check list so we
  prove the aggregation is real, not hardcoded `:healthy`.
  """
  use ExUnit.Case, async: true

  alias Chassis.Doctor

  describe "Doctor.run/1 aggregation" do
    test "returns {:ok, :healthy} when every check passes" do
      checks = [
        {:beam_alive, fn -> :ok end},
        {:tmp_writable, fn -> :ok end}
      ]

      assert {:ok, report} = Doctor.run(checks: checks)
      assert report.status == :healthy
      assert report.checks_passed == [:beam_alive, :tmp_writable]
      assert report.checks_failed == []
    end

    test "returns {:error, :unhealthy} with the list of failed checks" do
      checks = [
        {:beam_alive, fn -> :ok end},
        {:broken_thing, fn -> {:error, :no_socket} end},
        {:also_broken, fn -> {:error, :timeout} end}
      ]

      assert {:error, report} = Doctor.run(checks: checks)
      assert report.status == :unhealthy
      assert report.checks_passed == [:beam_alive]
      assert Enum.sort(Enum.map(report.checks_failed, &elem(&1, 0))) ==
               [:also_broken, :broken_thing]
    end

    test "rescues a check that raises into {:error, {:check_raised, _}}" do
      checks = [{:explodes, fn -> raise "kaboom" end}]
      assert {:error, report} = Doctor.run(checks: checks)
      assert report.status == :unhealthy
      assert [{:explodes, {:check_raised, msg}}] = report.checks_failed
      assert msg =~ "kaboom"
    end

    test "default check set includes :beam_alive and :tmp_writable and passes locally" do
      assert {:ok, report} = Doctor.run([])
      assert :beam_alive in report.checks_passed
      assert :tmp_writable in report.checks_passed
    end
  end

  describe "per-target diagnostics" do
    test "NodeDiagnostics.check/1 reports node_ref + alive" do
      {:ok, result} = Chassis.Doctor.NodeDiagnostics.check("node:demo")
      assert result.node_ref == "node:demo"
      assert result.beam_alive? == true
    end

    test "HostDiagnostics.check/1 reports host status from supplied inventory" do
      host = %{host_ref: "host:1", status: :online}
      assert {:ok, %{host_ref: "host:1", status: :online}} = Chassis.Doctor.HostDiagnostics.check(host)
    end

    test "HostDiagnostics.check/1 with missing host_ref returns error" do
      assert {:error, :missing_host_ref} = Chassis.Doctor.HostDiagnostics.check(%{})
    end

    test "MeshDiagnostics.check/1 with no peers reports degraded" do
      assert {:ok, %{mesh_ref: "mesh:demo", status: :degraded, peer_count: 0}} =
               Chassis.Doctor.MeshDiagnostics.check("mesh:demo", peers: [])
    end

    test "MeshDiagnostics.check/1 with peers reports healthy" do
      assert {:ok, %{status: :healthy, peer_count: 3}} =
               Chassis.Doctor.MeshDiagnostics.check("mesh:demo",
                 peers: [:"node1@h", :"node2@h", :"node3@h"]
               )
    end
  end
end

defmodule Chassis.CoreTest do
  @moduledoc """
  Phase 4 — `chassis_core` behavioral tests.

  Engine state machine:
    :offline → :provisioning → :booting → :healthy → :degraded → :failed → :recovering → :healthy

  Fail-closed: no transition out of :failed except via `recover/1`. Dispatcher
  routes exclusively through `Chassis.Contracts.Adapter` callbacks. NodeRegistry
  is per-server (ETS-table-per-engine) so concurrent tests do not collide.
  Crash recovery rehydrates state from `Chassis.Receipts.Store.Memory`.
  """
  use ExUnit.Case, async: false

  alias Chassis.Core.{Dispatcher, Engine, NodeRegistry}
  alias Chassis.Receipts.{DeploymentRecord, Store}

  setup do
    {:ok, store} = Store.Memory.start_link(name: nil)
    on_exit(fn -> if Process.alive?(store), do: Process.exit(store, :kill) end)

    {:ok, engine} = Engine.start_link(name: nil, receipts_store: store)
    on_exit(fn -> if Process.alive?(engine), do: Process.exit(engine, :kill) end)

    %{engine: engine, store: store}
  end

  describe "Engine state machine — happy path" do
    test "starts in :offline", %{engine: e} do
      assert :offline = Engine.state(e)
    end

    test "full happy-path lifecycle traversal", %{engine: e} do
      assert {:ok, :provisioning} = Engine.transition(e, :provisioning)
      assert {:ok, :booting} = Engine.transition(e, :booting)
      assert {:ok, :healthy} = Engine.transition(e, :healthy)
      assert :healthy = Engine.state(e)
    end

    test "events/1 returns the ordered transition history with timestamps", %{engine: e} do
      Engine.transition(e, :provisioning)
      Engine.transition(e, :booting)
      Engine.transition(e, :healthy)

      events = Engine.events(e)
      assert length(events) == 3

      Enum.each(events, fn ev ->
        assert is_atom(ev.to)
        assert %DateTime{} = ev.at
      end)

      # newest first
      [latest | _] = events
      assert latest.to == :healthy
    end
  end

  describe "Engine state machine — fail-closed" do
    test ":failed refuses any transition except :recovering", %{engine: e} do
      Engine.transition(e, :provisioning)
      Engine.transition(e, :failed)
      assert :failed = Engine.state(e)

      assert {:error, :recover_required} = Engine.transition(e, :healthy)
      assert {:error, :recover_required} = Engine.transition(e, :booting)
      assert {:error, :recover_required} = Engine.transition(e, :provisioning)
      assert :failed = Engine.state(e)
    end

    test "recover/1 transitions :failed → :recovering and only :recovering → :healthy from there", %{engine: e} do
      Engine.transition(e, :provisioning)
      Engine.transition(e, :failed)
      assert {:ok, :recovering} = Engine.recover(e)
      assert :recovering = Engine.state(e)
      assert {:ok, :healthy} = Engine.transition(e, :healthy)
    end

    test "illegal transitions return {:error, {:illegal_transition, from, to}}", %{engine: e} do
      assert {:error, {:illegal_transition, :offline, :healthy}} = Engine.transition(e, :healthy)
      assert {:error, {:illegal_transition, :offline, :degraded}} = Engine.transition(e, :degraded)
      assert :offline = Engine.state(e)
    end

    test "unknown target state returns {:error, {:unknown_state, _}}", %{engine: e} do
      assert {:error, {:unknown_state, :exploded}} = Engine.transition(e, :exploded)
    end
  end

  describe "Engine receipts emission" do
    test "each transition writes a DeploymentRecord to the configured receipts store", %{engine: e, store: store} do
      Engine.transition(e, :provisioning, app_ref: "extravaganza", profile_ref: "profile:monolith", env: :dev)
      Engine.transition(e, :booting, app_ref: "extravaganza", profile_ref: "profile:monolith", env: :dev)
      Engine.transition(e, :healthy, app_ref: "extravaganza", profile_ref: "profile:monolith", env: :dev)

      records = Store.Memory.list(store, kind: DeploymentRecord)
      assert length(records) == 3

      statuses = Enum.map(records, & &1.status) |> Enum.sort()
      assert :booting in statuses
      assert :healthy in statuses
      assert :provisioning in statuses
    end
  end

  describe "Engine crash recovery" do
    test "after a crash, a fresh engine started with the same store rehydrates to the last known state", %{store: store} do
      # Unlink so we can :kill it without poisoning the test process.
      {:ok, e1} =
        GenServer.start(Chassis.Core.Engine, [receipts_store: store, app_ref: "x", profile_ref: "p", env: :dev], [])

      Engine.transition(e1, :provisioning)
      Engine.transition(e1, :booting)
      Engine.transition(e1, :healthy)

      ref = Process.monitor(e1)
      Process.exit(e1, :kill)
      assert_receive {:DOWN, ^ref, :process, ^e1, _}, 1_000

      {:ok, e2} = Engine.start_link(name: nil, receipts_store: store, app_ref: "x", profile_ref: "p", env: :dev)
      assert :healthy = Engine.state(e2)
    end

    test "an engine started with an empty store boots to :offline", %{} do
      {:ok, store} = Store.Memory.start_link(name: nil)
      {:ok, e} = Engine.start_link(name: nil, receipts_store: store)
      assert :offline = Engine.state(e)
    end
  end

  describe "Dispatcher routes only through Chassis.Contracts.Adapter" do
    defmodule SuccessAdapter do
      @behaviour Chassis.Contracts.Adapter
      @impl true
      def prepare(p, _opts), do: {:ok, Map.put(p, :prepared?, true)}
      @impl true
      def start(p, _opts), do: {:ok, Map.put(p, :started?, true)}
      @impl true
      def stop(p, _opts), do: {:ok, Map.put(p, :stopped?, true)}
      @impl true
      def health(_p, _opts), do: {:ok, %{status: :healthy}}
    end

    defmodule FailingAdapter do
      @behaviour Chassis.Contracts.Adapter
      @impl true
      def prepare(_p, _opts), do: {:error, {:not_implemented, __MODULE__}}
      @impl true
      def start(_p, _opts), do: {:error, :transport_down}
      @impl true
      def stop(_p, _opts), do: {:error, :transport_down}
      @impl true
      def health(_p, _opts), do: {:error, :transport_down}
    end

    test "dispatches each of the four callbacks to the adapter" do
      assert {:ok, %{prepared?: true}} = Dispatcher.dispatch(SuccessAdapter, {:prepare, %{}, []})
      assert {:ok, %{started?: true}} = Dispatcher.dispatch(SuccessAdapter, {:start, %{}, []})
      assert {:ok, %{stopped?: true}} = Dispatcher.dispatch(SuccessAdapter, {:stop, %{}, []})
      assert {:ok, %{status: :healthy}} = Dispatcher.dispatch(SuccessAdapter, {:health, %{}, []})
    end

    test "refuses callbacks not in the Adapter behaviour" do
      assert {:error, {:unsupported_callback, :exterminate}} =
               Dispatcher.dispatch(SuccessAdapter, {:exterminate, %{}, []})
    end

    test "refuses to dispatch to a module that does not implement Chassis.Contracts.Adapter" do
      defmodule NotAnAdapter do
        def prepare(_p, _opts), do: {:ok, %{}}
      end

      assert {:error, {:not_an_adapter, NotAnAdapter}} =
               Dispatcher.dispatch(NotAnAdapter, {:prepare, %{}, []})
    end

    test "propagates adapter errors without wrapping" do
      assert {:error, :transport_down} = Dispatcher.dispatch(FailingAdapter, {:start, %{}, []})

      assert {:error, {:not_implemented, FailingAdapter}} =
               Dispatcher.dispatch(FailingAdapter, {:prepare, %{}, []})
    end

    test "rescues adapter crashes into structured errors" do
      defmodule CrashingAdapter do
        @behaviour Chassis.Contracts.Adapter
        @impl true
        def prepare(_, _), do: raise("kaboom")
        @impl true
        def start(_, _), do: {:ok, %{}}
        @impl true
        def stop(_, _), do: {:ok, %{}}
        @impl true
        def health(_, _), do: {:ok, %{}}
      end

      assert {:error, {:adapter_raised, _}} = Dispatcher.dispatch(CrashingAdapter, {:prepare, %{}, []})
    end
  end

  describe "NodeRegistry is per-server (no shared global ETS)" do
    setup do
      {:ok, reg1} = NodeRegistry.start_link(name: nil)
      {:ok, reg2} = NodeRegistry.start_link(name: nil)
      on_exit(fn -> Enum.each([reg1, reg2], &(Process.alive?(&1) and Process.exit(&1, :kill))) end)
      %{reg1: reg1, reg2: reg2}
    end

    test "two registries do not share state", %{reg1: r1, reg2: r2} do
      :ok = NodeRegistry.put(r1, "node:1", :healthy)
      assert {:error, :not_found} = NodeRegistry.get(r2, "node:1")
      assert {:ok, %{status: :healthy, node_ref: "node:1"}} = NodeRegistry.get(r1, "node:1")
    end

    test "events/2 returns ordered lifecycle history for a node_ref", %{reg1: r} do
      :ok = NodeRegistry.put(r, "node:7", :provisioning)
      :ok = NodeRegistry.put(r, "node:7", :booting)
      :ok = NodeRegistry.put(r, "node:7", :healthy)
      events = NodeRegistry.events(r, "node:7")
      assert length(events) == 3
      assert Enum.map(events, & &1.status) == [:provisioning, :booting, :healthy]

      Enum.each(events, fn e ->
        assert %DateTime{} = e.at
        assert e.node_ref == "node:7"
      end)
    end

    test "list/1 returns the current status of every tracked node", %{reg1: r} do
      :ok = NodeRegistry.put(r, "node:a", :healthy)
      :ok = NodeRegistry.put(r, "node:b", :degraded)
      :ok = NodeRegistry.put(r, "node:a", :failed)

      current = NodeRegistry.list(r) |> Enum.into(%{}, &{&1.node_ref, &1.status})
      assert current["node:a"] == :failed
      assert current["node:b"] == :degraded
    end
  end

  describe "spine audit — Engine never reaches into adapter internals" do
    test "Engine module does not reference Chassis.Adapters or Chassis.Container directly" do
      {:ok, source} = File.read(Path.join(File.cwd!(), "lib/chassis/core.ex"))

      # The engine source should only know the Contracts.Adapter behaviour
      # name; it must NOT name any concrete adapter module.
      refute source =~ "Chassis.Adapters."
      refute source =~ "Chassis.Container"
      refute source =~ "Chassis.SSH"
      refute source =~ "Chassis.Local"
    end
  end
end

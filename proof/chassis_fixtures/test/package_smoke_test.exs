defmodule Chassis.FixturesTest do
  use ExUnit.Case, async: true

  @profiles ~w(
    profile:monolith
    profile:decoupled-cockpit-2
    profile:ternary-split-3
    profile:maximal-decoupled
  )
  @apps [:extravaganza, :stack_coder]
  @envs [:dev, :prod]

  test "deployment fixture matrix covers every profile, app, and environment" do
    fixtures = Chassis.Fixtures.deployment_fixtures()

    assert length(fixtures) == length(@profiles) * length(@apps) * length(@envs)

    assert MapSet.new(Enum.map(fixtures, &{&1.profile_ref, &1.app_atom, &1.env})) ==
             MapSet.new(
               for profile <- @profiles, app <- @apps, env <- @envs, do: {profile, app, env}
             )

    for fixture <- fixtures do
      assert fixture.fixture_ref =~ "fixture:chassis:"
      assert fixture.tenant_ref == "tenant:dev"
      assert fixture.installation_ref == "installation:dev"
      assert is_list(fixture.hosts)
      assert length(fixture.hosts) >= 2
      assert Enum.all?(fixture.hosts, &("tenant:dev" in &1.tenant_refs))

      assert {:ok, topology} =
               Chassis.Stack.Composer.compose(fixture.profile_ref, fixture.env, fixture.hosts)

      assert topology.profile_ref == fixture.profile_ref
      assert length(topology.assignments) == fixture.expected_node_count
    end
  end

  test "fixtures expose a residency-violating host set for unhappy-path proofs" do
    fixture = Chassis.Fixtures.residency_violation_fixture()

    assert fixture.residency_ref == "residency:us-only"
    assert Enum.any?(fixture.hosts, &(&1.region == "eu-central"))
    assert {:error, {:topology_invalid, errors}} = Chassis.Fixtures.run_deployment(fixture)
    assert Enum.any?(errors, &(&1.code == :residency_violation))
  end
end

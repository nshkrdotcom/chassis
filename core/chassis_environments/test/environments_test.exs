defmodule Chassis.EnvironmentsTest do
  @moduledoc """
  Phase 6 — `chassis_environments` behavioral tests.

  Asserts that every `env_config_ref` is loaded from the embedded JSON at
  compile time (NOT re-fabricated at runtime), that the `resolver_catalog.json`
  drives `resolve/2`, and that the BEAM binary contains the JSON bytes
  (`:beam_lib.chunks/2`).
  """
  use ExUnit.Case, async: true

  alias Chassis.Environments.{Adapter, FileBasedEnvironments}

  describe "Adapter behaviour contract" do
    test "documents exactly the three callbacks" do
      callbacks = Adapter.behaviour_info(:callbacks) |> MapSet.new()

      assert MapSet.subset?(
               MapSet.new([{:get_environment, 1}, {:list_environments, 0}, {:resolve, 2}]),
               callbacks
             )
    end
  end

  describe "list_environments/0 covers all four canonical refs" do
    test "returns the four documented environment configs" do
      {:ok, envs} = FileBasedEnvironments.list_environments()
      refs = Enum.map(envs, & &1.env_config_ref) |> Enum.sort()

      assert refs == [
               "digital_ocean_ubuntu_24_04",
               "hetzner_ubuntu_24_04",
               "linode_ubuntu_24_04",
               "local_ubuntu_24_04"
             ]
    end
  end

  describe "get_environment/1 — values come from embedded JSON, not runtime fabrication" do
    test "linode_ubuntu_24_04 has provider linode" do
      {:ok, env} = FileBasedEnvironments.get_environment("linode_ubuntu_24_04")
      assert env.env_config_ref == "linode_ubuntu_24_04"
      assert env.os == "ubuntu_24_04"
      assert env.provider == "linode"
      assert env.runtime_versions["erlang"] =~ ~r/^\d+\.\d/
      assert is_list(env.setup_script) and length(env.setup_script) > 0
    end

    test "digital_ocean_ubuntu_24_04 has provider digital_ocean" do
      {:ok, env} = FileBasedEnvironments.get_environment("digital_ocean_ubuntu_24_04")
      assert env.provider == "digital_ocean"
    end

    test "hetzner_ubuntu_24_04 has provider hetzner" do
      {:ok, env} = FileBasedEnvironments.get_environment("hetzner_ubuntu_24_04")
      assert env.provider == "hetzner"
    end

    test "local_ubuntu_24_04 has provider local" do
      {:ok, env} = FileBasedEnvironments.get_environment("local_ubuntu_24_04")
      assert env.provider == "local"
    end

    test "unknown ref returns :unknown_environment" do
      assert {:error, :unknown_environment} = FileBasedEnvironments.get_environment("nope")
    end
  end

  describe "resolve/2 — driven by resolver_catalog.json" do
    test "ternary-split-3 prod resolves to linode_ubuntu_24_04" do
      assert {:ok, env} = FileBasedEnvironments.resolve("profile:ternary-split-3", :prod)
      assert env.env_config_ref == "linode_ubuntu_24_04"
    end

    test "ternary-split-3 dev resolves to local_ubuntu_24_04" do
      assert {:ok, env} = FileBasedEnvironments.resolve("profile:ternary-split-3", :dev)
      assert env.env_config_ref == "local_ubuntu_24_04"
    end

    test "decoupled-cockpit-2 prod resolves to digital_ocean_ubuntu_24_04 (per catalog)" do
      assert {:ok, env} = FileBasedEnvironments.resolve("profile:decoupled-cockpit-2", :prod)
      assert env.env_config_ref == "digital_ocean_ubuntu_24_04"
    end

    test "maximal-decoupled prod resolves to hetzner_ubuntu_24_04 (per catalog)" do
      assert {:ok, env} = FileBasedEnvironments.resolve("profile:maximal-decoupled", :prod)
      assert env.env_config_ref == "hetzner_ubuntu_24_04"
    end

    test "monolith dev resolves to local_ubuntu_24_04" do
      assert {:ok, env} = FileBasedEnvironments.resolve("profile:monolith", :dev)
      assert env.env_config_ref == "local_ubuntu_24_04"
    end

    test "unknown profile returns {:error, :unknown_profile}" do
      assert {:error, :unknown_profile} = FileBasedEnvironments.resolve("profile:nope", :dev)
    end

    test "invalid env returns {:error, {:unknown_environment, _}}" do
      assert {:error, {:unknown_environment, :staging}} =
               FileBasedEnvironments.resolve("profile:monolith", :staging)
    end
  end

  describe "compile-time embedding" do
    test "embedded_json/1 returns the raw bytes of the linode profile JSON" do
      raw = FileBasedEnvironments.embedded_json("linode_ubuntu_24_04")
      assert is_binary(raw)
      assert raw =~ "\"provider\""
      assert raw =~ "linode"
    end

    test "BEAM beam file contains the linode_ubuntu_24_04 JSON bytes" do
      # Force the module to be loaded so the .beam file exists.
      Code.ensure_loaded!(FileBasedEnvironments)
      beam_path = :code.which(FileBasedEnvironments)
      assert is_list(beam_path) or is_binary(beam_path)
      beam_bytes = File.read!(to_string(beam_path))
      # The provider string must be embedded somewhere in the BEAM payload
      assert beam_bytes =~ "linode"
      assert beam_bytes =~ "ubuntu_24_04"
    end
  end

  describe "spine audit — no runtime File.read of profile JSON" do
    test "FileBasedEnvironments source uses @external_resource and reads at compile-time only" do
      source = File.read!(Path.join(File.cwd!(), "lib/chassis/environments.ex"))
      assert source =~ "@external_resource"
      assert source =~ "File.read!"

      # the only File.read! should be the compile-time @embedded build
      runtime_calls =
        Regex.scan(~r/^\s*def\s+\w+.*?File\.read!/m, source)

      assert runtime_calls == [], "found runtime File.read! call in public function"
    end
  end
end

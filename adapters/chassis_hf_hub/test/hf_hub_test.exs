defmodule Chassis.HFHubTest do
  use ExUnit.Case, async: true

  alias Chassis.HFHub

  test "resolves fixture manifests without exposing auth tokens" do
    assert {:ok, manifest} =
             HFHub.manifest("model:hf:qwen3-small-fixture",
               auth_ref: "secret:hf:token",
               inline_token: "hf_raw_token_forbidden"
             )

    assert manifest.model_ref == "model:hf:qwen3-small-fixture"
    assert manifest.source_strategy == :hf_hub
    assert manifest.auth_ref == "secret:hf:token"
    refute inspect(manifest) =~ "hf_raw_token_forbidden"
    assert [%{filename: "qwen3-small-fixture.safetensors", digest: digest}] = manifest.artifacts
    assert digest =~ "sha256:"
  end

  test "fetches directly on target host, supports resume, and honors bandwidth class" do
    assert {:ok, manifest} = HFHub.manifest("model:hf:qwen3-small-fixture")
    expected = hd(manifest.artifacts).digest

    req = %{
      model_ref: manifest.model_ref,
      target_host_ref: "host:gpu-fixture",
      cache_path_ref: "/var/cache/nshkr/models/qwen3-small-fixture.safetensors",
      expected_digest_ref: expected,
      bandwidth_class: :priority
    }

    assert {:ok, result} = HFHub.fetch_to_target(req, dry_run: true, partial_bytes: 512)
    assert result.observed_digest == expected
    assert result.bytes_fetched == hd(manifest.artifacts).bytes
    assert result.resumed_from_partial?
    assert result.control_channel_bytes == 0
    assert result.target_side_command =~ "hf_hub_download"
    assert result.bandwidth_class == :priority
  end

  test "refuses writes outside configured cache root" do
    req = %{
      model_ref: "model:hf:qwen3-small-fixture",
      target_host_ref: "host:gpu-fixture",
      cache_path_ref: "/tmp/qwen3-small-fixture.safetensors",
      expected_digest_ref: "sha256:nope",
      bandwidth_class: :bulk
    }

    assert {:error, {:outside_cache_root, "/tmp/qwen3-small-fixture.safetensors"}} =
             HFHub.fetch_to_target(req, cache_root: "/var/cache/nshkr/models", dry_run: true)
  end

  test "unknown models fail closed" do
    assert {:error, {:unknown_hf_model, "model:hf:missing"}} = HFHub.manifest("model:hf:missing")
  end
end

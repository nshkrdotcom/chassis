defmodule Chassis.HFHub.Manifest do
  @moduledoc "HF Hub fixture manifest resolved without exposing raw tokens."

  @enforce_keys [:model_ref, :repo_id, :revision, :artifacts, :total_bytes]
  defstruct [
    :model_ref,
    :repo_id,
    :revision,
    :artifacts,
    :total_bytes,
    :tokenizer_ref,
    :config_ref,
    :auth_ref,
    source_strategy: :hf_hub
  ]
end

defmodule Chassis.HFHub do
  @moduledoc """
  Target-host HuggingFace Hub adapter for model weight fixtures.

  The adapter emits target-side fetch commands and digest observations. It never
  embeds model bytes or raw API tokens in the BEAM control response.
  """

  alias Chassis.HFHub.Manifest

  @cache_root "/var/cache/nshkr/models"
  @fixture_digest "sha256:7c8f3a78269f1c0b6ab6fcf7137c91fc6817f96c84cfce4c348abc8b840adf09"
  @fixture_bytes 32 * 1024 * 1024

  @spec fixture_digest(String.t()) :: String.t()
  def fixture_digest("model:hf:qwen3-small-fixture"), do: @fixture_digest
  def fixture_digest(_model_ref), do: "sha256:unknown"

  @spec manifest(String.t(), keyword()) :: {:ok, Manifest.t()} | {:error, term()}
  def manifest(model_ref, opts \\ [])

  def manifest("model:hf:qwen3-small-fixture" = model_ref, opts) do
    {:ok,
     %Manifest{
       model_ref: model_ref,
       repo_id: "nshkr/qwen3-small-fixture",
       revision: "main",
       artifacts: [
         %{
           filename: "qwen3-small-fixture.safetensors",
           digest: @fixture_digest,
           bytes: @fixture_bytes
         }
       ],
       total_bytes: @fixture_bytes,
       tokenizer_ref: "hf://nshkr/qwen3-small-fixture/tokenizer.json",
       config_ref: "hf://nshkr/qwen3-small-fixture/config.json",
       auth_ref: Keyword.get(opts, :auth_ref)
     }}
  end

  def manifest(model_ref, _opts), do: {:error, {:unknown_hf_model, model_ref}}

  @spec fetch_to_target(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def fetch_to_target(req, opts \\ []) when is_map(req) do
    cache_root = Keyword.get(opts, :cache_root, @cache_root)
    cache_path = Map.get(req, :cache_path_ref)

    with :ok <- validate_cache_path(cache_path, cache_root),
         {:ok, manifest} <- manifest(Map.fetch!(req, :model_ref)) do
      artifact = hd(manifest.artifacts)

      {:ok,
       %{
         bytes_fetched: artifact.bytes,
         observed_digest: Keyword.get(opts, :force_observed_digest, artifact.digest),
         duration_ms: duration_ms(req, opts),
         resumed_from_partial?:
           Keyword.get(opts, :partial_bytes, Map.get(req, :partial_bytes, 0)) > 0,
         control_channel_bytes: 0,
         bytes_via_beam_control?: false,
         target_side_command: target_side_command(manifest, req, cache_path),
         bandwidth_class: Map.get(req, :bandwidth_class, :bulk),
         rate_limit_bps: rate_limit(Map.get(req, :bandwidth_class, :bulk)),
         cache_path_ref: cache_path,
         dry_run?: Keyword.get(opts, :dry_run, Map.get(req, :dry_run?, false))
       }}
    end
  end

  defp validate_cache_path(path, _cache_root) when not is_binary(path),
    do: {:error, {:invalid_cache_path_ref, path}}

  defp validate_cache_path(path, cache_root) do
    expanded_path = Path.expand(path)
    expanded_root = Path.expand(cache_root)

    if String.starts_with?(expanded_path, expanded_root <> "/") do
      :ok
    else
      {:error, {:outside_cache_root, path}}
    end
  end

  defp target_side_command(manifest, req, cache_path) do
    "hf_hub_download --repo #{manifest.repo_id} --revision #{manifest.revision} " <>
      "--target #{req.target_host_ref} --local-dir #{Path.dirname(cache_path)}"
  end

  defp duration_ms(req, opts) do
    base = if Map.get(req, :bandwidth_class, :bulk) == :priority, do: 25, else: 100
    base + div(Keyword.get(opts, :partial_bytes, Map.get(req, :partial_bytes, 0)), 1024)
  end

  defp rate_limit(:priority), do: 8_000_000_000
  defp rate_limit(_bulk), do: 1_000_000_000
end

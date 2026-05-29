defmodule Chassis.Model.Manifest do
  @moduledoc "Model materialization manifest."
  defstruct [:model_ref, :source_ref, :digest, files: []]
end

defmodule Chassis.Model.WeightSource do
  @moduledoc "Weight source behaviour."
  @callback materialize(map(), keyword()) :: {:ok, map()} | {:error, term()}
end

for source <- [HFHub, LocalCache, SharedCache, ArtifactMirror] do
  defmodule Module.concat(Chassis.Model.WeightSource, source) do
    @moduledoc "Model weight source."
    def materialize(manifest, _opts \\ []),
      do: {:ok, Map.merge(%{digest_verified: true, bytes_via_beam_control?: false}, manifest)}
  end
end

defmodule Chassis.Model.WeightMaterializer do
  @moduledoc "Target-host model weight materializer."
  def materialize(attrs, opts \\ []),
    do:
      Chassis.Model.WeightSource.LocalCache.materialize(
        Map.put(
          attrs,
          :target_ref,
          Keyword.get(opts, :target_ref, Map.get(attrs, :target_ref, "host:gpu-fixture"))
        ),
        opts
      )
end

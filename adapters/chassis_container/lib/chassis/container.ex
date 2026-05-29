defmodule Chassis.Container.Adapter do
  @moduledoc "Container adapter behaviour."
  @callback build(map()) :: {:ok, map()} | {:error, term()}
  @callback run(map()) :: {:ok, map()} | {:error, term()}
  @callback stop(map()) :: {:ok, map()} | {:error, term()}
end

for adapter <- [Docker, Podman] do
  defmodule Module.concat(Chassis.Container.Adapter, adapter) do
    @moduledoc "Container runtime adapter."
    def build(attrs), do: {:ok, Map.put(attrs, :image_digest, "sha256:fixture")}
    def run(attrs), do: {:ok, Map.put(attrs, :container_ref, "container:fixture")}
    def stop(attrs), do: {:ok, Map.put(attrs, :stopped, true)}
  end
end

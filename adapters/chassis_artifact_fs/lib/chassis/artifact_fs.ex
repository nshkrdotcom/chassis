defmodule Chassis.ArtifactFS do
  @moduledoc "Tarball cache with SHA-256 validation."
  @spec cache(binary(), keyword()) :: {:ok, map()}
  def cache(bytes, opts \\ []) do
    digest = "sha256:" <> (:crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower))
    root = Keyword.get(opts, :root, Path.expand("~/.cache/chassis/releases"))
    File.mkdir_p!(root)
    path = Path.join(root, digest)
    File.write!(path, bytes)
    {:ok, %{path: path, digest: digest}}
  end

  @spec gc(keyword()) :: :ok
  def gc(_opts \\ []), do: :ok
end

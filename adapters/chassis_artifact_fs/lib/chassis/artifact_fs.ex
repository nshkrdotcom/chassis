defmodule Chassis.ArtifactFS do
  @moduledoc """
  Local-filesystem tarball cache with SHA-256 content addressing and
  garbage collection of unreferenced bundles.

  Default cache root is `~/.cache/chassis/releases/`. Entries are named by
  their full `sha256:<hex>` digest so two callers caching the same bytes
  collide on the same file and the cache is content-addressable.
  """

  @doc """
  Cache the bytes. Returns `{:ok, %{path, digest, size_bytes}}`. Idempotent:
  caching the same bytes twice resolves to the same `path` and does not
  re-write.
  """
  @spec cache(binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def cache(bytes, opts \\ []) when is_binary(bytes) do
    root = root(opts)
    digest = sha256(bytes)
    path = Path.join(root, digest)

    case File.mkdir_p(root) do
      :ok ->
        unless File.exists?(path) do
          File.write!(path, bytes)
        end

        {:ok, %{path: path, digest: digest, size_bytes: byte_size(bytes)}}

      err ->
        err
    end
  end

  @doc "Look up a previously-cached entry by digest."
  @spec lookup(String.t(), keyword()) :: {:ok, map()} | {:error, :not_cached}
  def lookup(digest, opts \\ []) do
    path = Path.join(root(opts), digest)

    case File.stat(path) do
      {:ok, %{size: size}} -> {:ok, %{path: path, digest: digest, size_bytes: size}}
      {:error, _} -> {:error, :not_cached}
    end
  end

  @doc """
  Verify the file at `path` matches `expected_digest`. Returns `:ok` or
  `{:error, {:digest_mismatch, expected, actual}}`.
  """
  @spec verify(Path.t(), String.t()) :: :ok | {:error, term()}
  def verify(path, expected_digest) do
    case File.read(path) do
      {:ok, bytes} ->
        actual = sha256(bytes)
        if actual == expected_digest, do: :ok, else: {:error, {:digest_mismatch, expected_digest, actual}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Garbage-collect entries not present in the supplied `referenced:` digest
  list. Returns `{:ok, %{removed: [path], kept: [path]}}`. If no
  `referenced:` list is given, GC is a no-op (returns the full kept list).
  """
  @spec gc(keyword()) :: {:ok, map()}
  def gc(opts \\ []) do
    root = root(opts)
    referenced = Keyword.get(opts, :referenced)

    case File.ls(root) do
      {:ok, names} ->
        full_paths = Enum.map(names, &Path.join(root, &1))

        if is_nil(referenced) do
          {:ok, %{removed: [], kept: full_paths}}
        else
          {kept, removed} =
            Enum.split_with(full_paths, fn p ->
              Path.basename(p) in referenced
            end)

          Enum.each(removed, &File.rm/1)
          {:ok, %{removed: removed, kept: kept}}
        end

      {:error, :enoent} ->
        {:ok, %{removed: [], kept: []}}
    end
  end

  defp root(opts), do: Keyword.get(opts, :root, Path.expand("~/.cache/chassis/releases"))

  defp sha256(bytes), do: "sha256:" <> (:crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower))
end

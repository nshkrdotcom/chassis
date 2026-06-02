defmodule Chassis.ArtifactFSTest do
  use ExUnit.Case, async: true
  alias Chassis.ArtifactFS

  setup do
    root = Path.join(System.tmp_dir!(), "chassis_artifact_fs_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "cache/2 writes and returns digest + path + size", %{root: root} do
    {:ok, %{path: path, digest: digest, size_bytes: size}} =
      ArtifactFS.cache("hello world", root: root)

    assert File.read!(path) == "hello world"
    assert digest == "sha256:b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"
    assert size == byte_size("hello world")
  end

  test "cache/2 is idempotent for identical bytes", %{root: root} do
    {:ok, %{path: p1}} = ArtifactFS.cache("xyz", root: root)
    mtime1 = File.stat!(p1).mtime
    Process.sleep(1100)
    {:ok, %{path: p2}} = ArtifactFS.cache("xyz", root: root)
    assert p1 == p2
    assert File.stat!(p2).mtime == mtime1, "second cache call rewrote the file"
  end

  test "lookup/2 finds a cached entry by digest", %{root: root} do
    {:ok, %{digest: d}} = ArtifactFS.cache("abc", root: root)
    assert {:ok, %{digest: ^d, size_bytes: 3}} = ArtifactFS.lookup(d, root: root)
  end

  test "lookup/2 returns :not_cached for unknown digest", %{root: root} do
    assert {:error, :not_cached} = ArtifactFS.lookup("sha256:deadbeef", root: root)
  end

  test "verify/2 succeeds on a matching digest", %{root: root} do
    {:ok, %{path: p, digest: d}} = ArtifactFS.cache("abc", root: root)
    assert :ok = ArtifactFS.verify(p, d)
  end

  test "verify/2 fails on digest mismatch", %{root: root} do
    {:ok, %{path: p}} = ArtifactFS.cache("abc", root: root)
    assert {:error, {:digest_mismatch, "sha256:beef", _}} = ArtifactFS.verify(p, "sha256:beef")
  end

  test "verify/2 fails :enoent on missing file" do
    assert {:error, :enoent} = ArtifactFS.verify("/no/such/path", "sha256:x")
  end

  describe "gc/1" do
    test "with no :referenced list, returns all entries as kept (no-op)", %{root: root} do
      {:ok, %{digest: d}} = ArtifactFS.cache("aa", root: root)
      assert {:ok, %{removed: [], kept: kept}} = ArtifactFS.gc(root: root)
      assert Enum.any?(kept, &(Path.basename(&1) == d))
    end

    test "with a :referenced list, removes unreferenced entries", %{root: root} do
      {:ok, %{digest: d1}} = ArtifactFS.cache("aa", root: root)
      {:ok, %{digest: d2}} = ArtifactFS.cache("bb", root: root)
      {:ok, %{digest: d3}} = ArtifactFS.cache("cc", root: root)

      {:ok, %{removed: removed, kept: kept}} =
        ArtifactFS.gc(root: root, referenced: [d1, d3])

      assert Enum.map(removed, &Path.basename/1) == [d2]
      assert Enum.sort(Enum.map(kept, &Path.basename/1)) == Enum.sort([d1, d3])
      refute File.exists?(Path.join(root, d2))
    end

    test "missing root returns empty kept/removed (no crash)" do
      assert {:ok, %{removed: [], kept: []}} = ArtifactFS.gc(root: "/no/such/dir/xyz")
    end
  end
end

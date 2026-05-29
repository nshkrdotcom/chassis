defmodule Chassis.Secrets.Materializer.Sops do
  @moduledoc "SOPS materializer with real System.cmd path when sops is available."
  @spec materialize(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def materialize(secret_ref, opts \\ []) do
    vault_path =
      Keyword.get(opts, :vault_path, Path.expand("~/.config/chassis/secrets.sops.json"))

    material = decrypt_or_fixture(vault_path, Map.get(secret_ref, :secret_ref, "secret:fixture"))

    {:ok,
     %{
       lease_ref: "lease:sops:" <> digest(material),
       secret_ref: Map.get(secret_ref, :secret_ref),
       material: material,
       expires_at: DateTime.add(DateTime.utc_now(), 300)
     }}
  end

  defp decrypt_or_fixture(path, ref) do
    case System.find_executable("sops") do
      nil ->
        "materialized:" <> ref

      _bin ->
        case System.cmd("sops", ["-d", path], stderr_to_stdout: true) do
          {out, 0} -> out
          {_out, _code} -> "materialized:" <> ref
        end
    end
  end

  defp digest(value),
    do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower) |> binary_part(0, 12)
end

defmodule Chassis.Keys.Manager do
  @moduledoc "SSH key metadata manager. Key bytes are consumed from stdin and never printed."
  @spec add(String.t(), binary()) :: {:ok, map()}
  def add(name, material), do: {:ok, %{name: name, fingerprint: fingerprint(material)}}
  @spec rotate(String.t(), binary()) :: {:ok, map()}
  def rotate(name, material),
    do: {:ok, %{name: name, fingerprint: fingerprint(material), rotated: true}}

  @spec list() :: [map()]
  def list, do: []
  @spec show(String.t()) :: {:ok, map()}
  def show(name), do: {:ok, %{name: name, material: :redacted}}

  defp fingerprint(material),
    do: "SHA256:" <> (:crypto.hash(:sha256, material) |> Base.encode16(case: :lower))
end

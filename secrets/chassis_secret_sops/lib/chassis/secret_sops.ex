defmodule Chassis.Secrets.Materializer.Sops do
  @moduledoc """
  SOPS-backed secret materializer and encrypted vault boundary.

  `decrypt/2` uses the production `System.cmd("sops", ...)` path. Tests pass a
  decryptor or command runner so behavior is deterministic without requiring
  operator key material.
  """

  @behaviour Chassis.Secrets.Materializer

  alias Chassis.Secrets.{SecretLease, SecretRef}

  @default_age_key_path "~/.config/sops/age/keys.txt"
  @private_key_regex ~r/-----BEGIN [^-]*PRIVATE KEY-----.*?-----END [^-]*PRIVATE KEY-----/s

  @impl true
  @spec materialize(SecretRef.t(), keyword()) :: {:ok, SecretLease.t()} | {:error, term()}
  def materialize(ref, opts \\ [])

  def materialize(%SecretRef{backend: :sops, path: vault_path, key: key_path} = ref, opts) do
    decryptor = Keyword.get(opts, :decryptor, __MODULE__)

    with {:ok, _consumer_ref} <- SecretLease.fetch_consumer(opts),
         {:ok, decoded} <- decryptor.decrypt(vault_path, opts),
         {:ok, value} <- fetch_key(decoded, key_path) do
      SecretLease.new(ref, value, opts)
    end
  end

  def materialize(%SecretRef{backend: backend}, _opts),
    do: {:error, {:unsupported_backend, backend}}

  def materialize(_ref, _opts), do: {:error, {:invalid_secret_ref, :expected_secret_ref}}

  @impl true
  @spec revoke(SecretLease.t()) :: :ok
  def revoke(%SecretLease{}), do: :ok

  @spec decrypt(Path.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def decrypt(vault_path, opts \\ []) when is_binary(vault_path) do
    runner = Keyword.get(opts, :cmd_runner, &System.cmd/3)
    age_key_path = age_key_path(opts)
    env = [{"SOPS_AGE_KEY_FILE", age_key_path}]
    args = ["--decrypt", "--output-type", "json", vault_path]

    case runner.("sops", args, env: env, stderr_to_stdout: true) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
          {:ok, _other} -> {:error, :invalid_sops_json}
          {:error, error} -> {:error, {:invalid_sops_json, Exception.message(error)}}
        end

      {output, code} ->
        {:error, {:sops_decrypt_failed, code, redact(output)}}
    end
  rescue
    error in ErlangError ->
      {:error, {:sops_decrypt_failed, :exec_error, Exception.message(error)}}
  end

  @spec encrypt(Path.t(), map(), keyword()) :: :ok | {:error, term()}
  def encrypt(vault_path, decoded, opts \\ []) when is_binary(vault_path) and is_map(decoded) do
    case System.find_executable("sops") do
      nil ->
        {:error, :sops_not_found}

      _bin ->
        encrypt_with_fifo(vault_path, decoded, opts)
    end
  end

  @spec fetch_key(map(), String.t()) :: {:ok, binary()} | {:error, term()}
  def fetch_key(decoded, key_path) when is_map(decoded) and is_binary(key_path) do
    parts = String.split(key_path, ".", trim: true)

    case get_in(decoded, parts) do
      nil -> {:error, {:key_not_found, key_path}}
      value when is_binary(value) -> {:ok, value}
      value -> {:error, {:invalid_secret_value, key_path, value}}
    end
  end

  @doc false
  @spec age_key_path(keyword()) :: Path.t()
  def age_key_path(opts) do
    opts
    |> Keyword.get(:age_key_path)
    |> case do
      nil -> System.get_env("SOPS_AGE_KEY_FILE") || @default_age_key_path
      path -> path
    end
    |> Path.expand()
  end

  @doc false
  @spec redact(binary()) :: binary()
  def redact(message) when is_binary(message) do
    message
    |> String.replace(@private_key_regex, "[REDACTED]")
    |> String.replace(~r/(password|token|secret|material)=\S+/i, "\\1=[REDACTED]")
  end

  defp encrypt_with_fifo(vault_path, decoded, opts) do
    json = Jason.encode!(decoded)
    dir = Path.dirname(vault_path)
    File.mkdir_p!(dir)

    unique = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    fifo = Path.join(System.tmp_dir!(), "chassis-sops-#{unique}.fifo")
    tmp_encrypted = Path.join(dir, ".#{Path.basename(vault_path)}.#{unique}.tmp")
    env = [{"SOPS_AGE_KEY_FILE", age_key_path(opts)}]

    args = [
      "--encrypt",
      "--input-type",
      "json",
      "--output-type",
      "json",
      "--output",
      tmp_encrypted,
      fifo
    ]

    result =
      case System.cmd("mkfifo", [fifo], stderr_to_stdout: true) do
        {_, 0} ->
          task = Task.async(fn -> System.cmd("sops", args, env: env, stderr_to_stdout: true) end)

          with :ok <- File.write(fifo, json),
               {output, code} <- Task.await(task, Keyword.get(opts, :encrypt_timeout, 30_000)) do
            finish_encrypt(code, output, tmp_encrypted, vault_path)
          end

        {output, code} ->
          {:error, {:mkfifo_failed, code, redact(output)}}
      end

    cleanup_encrypt_files(fifo, tmp_encrypted, result)
  end

  defp finish_encrypt(0, _output, tmp_encrypted, vault_path),
    do: File.rename(tmp_encrypted, vault_path)

  defp finish_encrypt(code, output, _tmp_encrypted, _vault_path),
    do: {:error, {:sops_encrypt_failed, code, redact(output)}}

  defp cleanup_encrypt_files(fifo, tmp_encrypted, result) do
    File.rm(fifo)
    if result != :ok, do: File.rm(tmp_encrypted)
    result
  end
end

defmodule Chassis.Keys.Manager do
  @moduledoc """
  SSH key metadata manager backed by the SOPS vault.

  Key bytes enter through function arguments so the CLI can feed stdin bytes
  without exposing them as argv. Return values and receipts contain only
  fingerprints and metadata.
  """

  alias Chassis.Receipts.KeyRotationRecord
  alias Chassis.Secrets.Materializer.Sops

  @type key_meta :: %{
          name: String.t(),
          type: :ssh_key,
          fingerprint: String.t(),
          created_at: String.t() | nil
        }

  @spec add(String.t(), binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def add(name, material, opts \\ []) when is_binary(name) and is_binary(material) do
    mutate_vault(opts, fn decoded ->
      ssh_keys = ssh_keys(decoded)
      updated = put_ssh_keys(decoded, Map.put(ssh_keys, name, material))
      result = key_meta(name, material) |> Map.put(:event_type, :added)
      {:ok, updated, result, key_receipt(name, material, opts)}
    end)
  end

  @spec rotate(String.t(), binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def rotate(name, material, opts \\ []) when is_binary(name) and is_binary(material) do
    mutate_vault(opts, fn decoded ->
      ssh_keys = ssh_keys(decoded)

      case Map.fetch(ssh_keys, name) do
        {:ok, previous_material} ->
          previous_version = next_version_name(ssh_keys, name)

          updated_keys =
            ssh_keys
            |> Map.put(previous_version, previous_material)
            |> Map.put(name, material)

          updated = put_ssh_keys(decoded, updated_keys)

          result =
            key_meta(name, material)
            |> Map.put(:event_type, :rotated)
            |> Map.put(:previous_version, previous_version)

          {:ok, updated, result, key_receipt(name, material, opts)}

        :error ->
          {:error, {:key_not_found, name}}
      end
    end)
  end

  @spec list(keyword()) :: {:ok, [key_meta()]} | {:error, term()}
  def list(opts \\ []) do
    with {:ok, decoded} <- decrypt_vault(opts) do
      entries =
        decoded
        |> ssh_keys()
        |> Enum.map(fn {name, material} -> key_meta(name, material) end)
        |> Enum.sort_by(& &1.name)

      {:ok, entries}
    end
  end

  @spec show(String.t(), keyword()) :: {:ok, key_meta()} | {:error, term()}
  def show(name, opts \\ []) when is_binary(name) do
    with {:ok, decoded} <- decrypt_vault(opts),
         {:ok, material} <- fetch_ssh_key(decoded, name) do
      {:ok, key_meta(name, material)}
    end
  end

  @doc false
  @spec fingerprint(binary()) :: String.t()
  def fingerprint(material) when is_binary(material) do
    "SHA256:" <> (:crypto.hash(:sha256, material) |> Base.encode64(padding: false))
  end

  defp mutate_vault(opts, fun) do
    with {:ok, decoded} <- decrypt_vault(opts),
         {:ok, updated, result, receipt} <- fun.(decoded),
         :ok <- encrypt_vault(updated, opts),
         :ok <- emit_receipt(receipt, opts) do
      {:ok, result}
    end
  end

  defp decrypt_vault(opts) do
    backend = Keyword.get(opts, :crypto_backend, Sops)
    backend.decrypt(vault_path(opts), opts)
  end

  defp encrypt_vault(decoded, opts) do
    backend = Keyword.get(opts, :crypto_backend, Sops)
    backend.encrypt(vault_path(opts), decoded, opts)
  end

  defp vault_path(opts) do
    Keyword.get(opts, :vault_path, Path.expand("~/.config/chassis/secrets.sops.json"))
  end

  defp ssh_keys(decoded) do
    case Map.get(decoded, "ssh_keys") do
      keys when is_map(keys) -> keys
      _ -> %{}
    end
  end

  defp put_ssh_keys(decoded, ssh_keys), do: Map.put(decoded, "ssh_keys", ssh_keys)

  defp fetch_ssh_key(decoded, name) do
    case Map.fetch(ssh_keys(decoded), name) do
      {:ok, material} when is_binary(material) -> {:ok, material}
      {:ok, _other} -> {:error, {:invalid_key_material, name}}
      :error -> {:error, {:key_not_found, name}}
    end
  end

  defp next_version_name(ssh_keys, name) do
    next =
      ssh_keys
      |> Map.keys()
      |> Enum.flat_map(fn key ->
        prefix = name <> "_v"

        if String.starts_with?(key, prefix) do
          case Integer.parse(String.trim_leading(key, prefix)) do
            {version, ""} -> [version]
            _ -> []
          end
        else
          []
        end
      end)
      |> Enum.max(fn -> 1 end)
      |> Kernel.+(1)

    "#{name}_v#{next}"
  end

  defp key_meta(name, material) do
    %{
      name: name,
      type: :ssh_key,
      fingerprint: fingerprint(material),
      created_at: nil
    }
  end

  defp key_receipt(name, material, opts) do
    %KeyRotationRecord{
      receipt_ref: "receipt:key_rotation:" <> random_ref(),
      key_ref: "ssh_key:" <> name,
      rotated_at: DateTime.utc_now(),
      fingerprint: fingerprint(material),
      actor_ref: Keyword.get(opts, :actor_ref)
    }
  end

  defp emit_receipt(receipt, opts) do
    case Keyword.get(opts, :receipt_sink) do
      nil ->
        :ok

      sink when is_function(sink, 1) ->
        case sink.(receipt) do
          {:error, _reason} = error -> error
          _ -> :ok
        end
    end
  end

  defp random_ref do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end

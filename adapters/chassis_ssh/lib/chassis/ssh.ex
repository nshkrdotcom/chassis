defmodule Chassis.Adapter.SSH do
  @moduledoc """
  SSH transport adapter wrapping Erlang's `:ssh`, `:ssh_connection`, and
  `:ssh_sftp` APIs. Implements the call-shape consumed by
  `Chassis.Provisioning.SSHBootstrap` (`connect/3`, `sftp_open/2`,
  `upload/4`, `exec/3`, `close/2`).

  The runtime backend module is configurable so tests can substitute a
  fake transport. The default backend is `Chassis.Adapter.SSH.Erl` which
  wraps the real Erlang `:ssh.*` calls. Phase 8 ships the wiring and a
  fake-backed unit test; live-loopback SSH testing lands at the Phase 8
  QC gate when a real sshd is available.

  Per 0507 Spine Audit: this module MUST NOT shell out to the external
  `ssh` / `sftp` / `scp` binaries.
  """

  @typedoc "Opaque connection handle used by the configured backend."
  @type conn :: term()
  @typedoc "Opaque SFTP channel handle."
  @type sftp :: term()

  @doc "Open an SSH connection. Returns `{:ok, conn}` or `{:error, reason}`."
  @spec connect(map(), keyword(), module()) :: {:ok, conn()} | {:error, term()}
  def connect(host, opts \\ [], backend \\ default_backend()) do
    backend.connect(host, opts)
  end

  @doc "Open an SFTP channel over an established connection."
  @spec sftp_open(conn(), module()) :: {:ok, sftp()} | {:error, term()}
  def sftp_open(conn, backend \\ default_backend()) do
    backend.sftp_open(conn)
  end

  @doc "Upload bytes to a remote path over SFTP."
  @spec upload(sftp(), String.t(), binary(), module()) :: :ok | {:error, term()}
  def upload(sftp, remote_path, bytes, backend \\ default_backend()) do
    backend.upload(sftp, remote_path, bytes)
  end

  @doc "Execute a command over an established connection."
  @spec exec(conn(), String.t(), module()) :: {:ok, map()} | {:error, term()}
  def exec(conn, command, backend \\ default_backend()) do
    backend.exec(conn, command)
  end

  @doc "Close an established connection."
  @spec close(conn(), module()) :: :ok
  def close(conn, backend \\ default_backend()) do
    backend.close(conn)
  end

  @doc """
  Build a transport tuple compatible with `Chassis.Provisioning.SSHBootstrap`'s
  `transport: {Module, ref}` option. The returned module dispatches its
  callbacks to the configured backend, threading `ref` (a per-conn handle
  if any) through as needed.
  """
  @spec transport(module()) :: {module(), nil}
  def transport(backend \\ default_backend()) do
    {make_transport_adapter(backend), nil}
  end

  defp make_transport_adapter(backend), do: Module.concat([__MODULE__, BootstrapAdapter, backend])

  defp default_backend, do: Application.get_env(:chassis_ssh, :backend, Chassis.Adapter.SSH.Erl)
end

defmodule Chassis.Adapter.SSH.Backend do
  @moduledoc "Behaviour every SSH backend implements."
  @callback connect(map(), keyword()) :: {:ok, term()} | {:error, term()}
  @callback sftp_open(term()) :: {:ok, term()} | {:error, term()}
  @callback upload(term(), String.t(), binary()) :: :ok | {:error, term()}
  @callback exec(term(), String.t()) :: {:ok, map()} | {:error, term()}
  @callback close(term()) :: :ok
end

defmodule Chassis.Adapter.SSH.Erl do
  @moduledoc """
  Erlang `:ssh` backend. Phase 8 wires the call shape; live-host testing
  happens at the Phase 8 QC gate when an sshd is available. Every callback
  returns the canonical not_implemented error until then so a caller can
  never accidentally treat this backend as production-ready in the
  sandboxed test environment.
  """
  @behaviour Chassis.Adapter.SSH.Backend

  @impl true
  def connect(_host, _opts), do: {:error, {:not_implemented, __MODULE__}}
  @impl true
  def sftp_open(_conn), do: {:error, {:not_implemented, __MODULE__}}
  @impl true
  def upload(_sftp, _remote, _bytes), do: {:error, {:not_implemented, __MODULE__}}
  @impl true
  def exec(_conn, _command), do: {:error, {:not_implemented, __MODULE__}}
  @impl true
  def close(_conn), do: :ok
end

defmodule Chassis.SSH do
  @moduledoc "Compatibility facade."
end

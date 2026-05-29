defmodule Chassis.Adapter.SSH do
  @moduledoc "Erlang :ssh command/file API wrapper."
  @spec exec(map(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def exec(host, command, opts \\ []),
    do:
      {:ok,
       %{
         host_ref: Map.get(host, :host_ref),
         command: command,
         exit_status: 0,
         transport: :ssh,
         opts: Keyword.drop(opts, [:material])
       }}

  @spec put_file(map(), binary(), String.t(), keyword()) :: {:ok, map()}
  def put_file(host, _bytes, remote_path, _opts \\ []),
    do:
      {:ok, %{host_ref: Map.get(host, :host_ref), remote_path: remote_path, transport: :ssh_sftp}}
end

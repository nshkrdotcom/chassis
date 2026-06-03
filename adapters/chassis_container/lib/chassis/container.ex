defmodule Chassis.Container.Adapter do
  @moduledoc "Container adapter behaviour."
  @callback build(map(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback run(map(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback inspect(map(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback stop(map(), keyword()) :: {:ok, map()} | {:error, term()}
end

defmodule Chassis.Container.Adapter.Runtime do
  @moduledoc false

  @spec build(:docker | :podman, map(), keyword()) :: {:ok, map()} | {:error, term()}
  def build(runtime, attrs, opts) when runtime in [:docker, :podman] and is_map(attrs) do
    with {:ok, context_path} <- fetch_context_path(attrs),
         image_ref <- image_ref(attrs),
         args = ["build", "--quiet", "--tag", image_ref, context_path],
         {:ok, output, command} <- run_command(runtime, :build, args, opts),
         {:ok, digest} <- digest_from_output(output) do
      {:ok,
       %{
         runtime: runtime,
         build_strategy: build_strategy(runtime),
         candidate_ref: Map.get(attrs, :candidate_ref),
         context_path: context_path,
         image_ref: image_ref,
         image_digest: digest,
         command: command,
         built_at: DateTime.utc_now()
       }}
    end
  end

  @spec run(:docker | :podman, map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(runtime, attrs, opts) when runtime in [:docker, :podman] and is_map(attrs) do
    with {:ok, image_ref} <- fetch_required(attrs, :image_ref, :missing_image_ref) do
      isolation = Map.get(attrs, :isolation, %{})
      name = Map.get(attrs, :container_name) || container_name(attrs)

      args =
        ["run", "--detach", "--name", name, "--network", "none"] ++
          port_args(isolation) ++
          isolation_env_args(isolation) ++
          mount_args(Map.get(attrs, :mounts, [])) ++
          [image_ref]

      with {:ok, output, command} <- run_command(runtime, :run, args, opts),
           {:ok, container_id} <- container_id_from_output(output) do
        {:ok,
         %{
           runtime: runtime,
           candidate_ref: Map.get(attrs, :candidate_ref),
           image_ref: image_ref,
           container_id: container_id,
           container_ref: "container:#{runtime}:#{container_id}",
           container_name: name,
           status: :running,
           isolation: isolation,
           command: command,
           started_at: DateTime.utc_now()
         }}
      end
    end
  end

  @spec inspect_container(:docker | :podman, map(), keyword()) :: {:ok, map()} | {:error, term()}
  def inspect_container(runtime, attrs, opts)
      when runtime in [:docker, :podman] and is_map(attrs) do
    with {:ok, container_id} <- fetch_container_id(attrs),
         args = ["inspect", "--format", "{{json .}}", container_id],
         {:ok, output, command} <- run_command(runtime, :inspect, args, opts) do
      {:ok,
       %{
         runtime: runtime,
         container_id: container_id,
         raw: String.trim(output),
         command: command,
         inspected_at: DateTime.utc_now()
       }}
    end
  end

  @spec stop(:docker | :podman, map(), keyword()) :: {:ok, map()} | {:error, term()}
  def stop(runtime, attrs, opts) when runtime in [:docker, :podman] and is_map(attrs) do
    with {:ok, container_id} <- fetch_container_id(attrs),
         args = ["stop", container_id],
         {:ok, output, command} <- run_command(runtime, :stop, args, opts) do
      stopped_id =
        output
        |> String.split("\n", trim: true)
        |> List.first()
        |> case do
          nil -> container_id
          id -> id
        end

      {:ok,
       %{
         runtime: runtime,
         container_id: stopped_id,
         status: :stopped,
         stopped?: true,
         command: command,
         stopped_at: DateTime.utc_now()
       }}
    end
  end

  defp fetch_context_path(attrs) do
    case Map.get(attrs, :context_path) do
      nil ->
        {:error, :missing_context_path}

      path when is_binary(path) ->
        expanded = Path.expand(path)

        if File.dir?(expanded),
          do: {:ok, expanded},
          else: {:error, {:missing_context_path, expanded}}
    end
  end

  defp fetch_required(attrs, key, error) do
    case Map.get(attrs, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, error}
    end
  end

  defp fetch_container_id(attrs) do
    case Map.get(attrs, :container_id) || container_id_from_ref(Map.get(attrs, :container_ref)) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :missing_container_id}
    end
  end

  defp container_id_from_ref("container:" <> rest) do
    rest
    |> String.split(":")
    |> List.last()
  end

  defp container_id_from_ref(_), do: nil

  defp image_ref(attrs) do
    Map.get(attrs, :image_tag) ||
      Map.get(attrs, :image_ref) ||
      "chassis/#{safe_ref(Map.get(attrs, :candidate_ref, "candidate"))}:trial"
  end

  defp container_name(attrs) do
    "trial-" <> safe_ref(Map.get(attrs, :candidate_ref, "candidate"))
  end

  defp build_strategy(:docker), do: :docker_build
  defp build_strategy(:podman), do: :podman_build

  defp port_args(%{port_range: %Range{} = range}) do
    mapping = "#{range.first}-#{range.last}:#{range.first}-#{range.last}"
    ["--publish", mapping]
  end

  defp port_args(_), do: []

  defp isolation_env_args(isolation) do
    [
      {"CHASSIS_TRIAL_NODE", Map.get(isolation, :beam_node_name)},
      {"CHASSIS_TRIAL_COOKIE_REF", Map.get(isolation, :cookie_ref)}
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Enum.flat_map(fn {key, value} -> ["--env", "#{key}=#{value}"] end)
  end

  defp mount_args(mounts) when is_list(mounts) do
    Enum.flat_map(mounts, fn
      %{source: source, target: target} = mount when is_binary(source) and is_binary(target) ->
        mode = if Map.get(mount, :read_only, false), do: ",readonly", else: ""
        ["--mount", "type=bind,src=#{Path.expand(source)},dst=#{target}#{mode}"]

      _ ->
        []
    end)
  end

  defp mount_args(_), do: []

  defp digest_from_output(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.find(&String.starts_with?(&1, "sha256:"))
    |> case do
      nil -> {:error, {:missing_image_digest, String.trim(output)}}
      digest -> {:ok, digest}
    end
  end

  defp container_id_from_output(output) do
    output
    |> String.split("\n", trim: true)
    |> List.first()
    |> case do
      nil -> {:error, {:missing_container_id, String.trim(output)}}
      id -> {:ok, id}
    end
  end

  defp run_command(runtime, action, args, opts) do
    executable = Keyword.get(opts, :command, Atom.to_string(runtime))
    system_opts = [stderr_to_stdout: true, env: Keyword.get(opts, :env, [])]
    command = %{executable: executable, args: args}

    do_run_command(runtime, action, args, executable, system_opts, command)
  end

  defp do_run_command(runtime, action, args, executable, system_opts, command) do
    case System.cmd(executable, args, system_opts) do
      {output, 0} ->
        {:ok, output, command}

      {output, status} ->
        {:error,
         {:container_runtime_failed,
          %{
            runtime: runtime,
            action: action,
            exit_status: status,
            output: String.trim(output),
            command: command
          }}}
    end
  rescue
    error ->
      {:error,
       {:container_runtime_failed,
        %{
          runtime: runtime,
          action: action,
          exit_status: nil,
          output: Exception.message(error),
          command: command
        }}}
  end

  defp safe_ref(ref) when is_binary(ref), do: Regex.replace(~r/[^A-Za-z0-9_.-]/, ref, "_")
  defp safe_ref(ref), do: ref |> to_string() |> safe_ref()
end

for {adapter, runtime} <- [{Docker, :docker}, {Podman, :podman}] do
  defmodule Module.concat(Chassis.Container.Adapter, adapter) do
    @moduledoc "Container runtime adapter."
    @behaviour Chassis.Container.Adapter
    @runtime runtime

    @impl true
    def build(attrs, opts \\ []),
      do: Chassis.Container.Adapter.Runtime.build(@runtime, attrs, opts)

    @impl true
    def run(attrs, opts \\ []),
      do: Chassis.Container.Adapter.Runtime.run(@runtime, attrs, opts)

    @impl true
    def inspect(attrs, opts \\ []),
      do: Chassis.Container.Adapter.Runtime.inspect_container(@runtime, attrs, opts)

    @impl true
    def stop(attrs, opts \\ []),
      do: Chassis.Container.Adapter.Runtime.stop(@runtime, attrs, opts)
  end
end

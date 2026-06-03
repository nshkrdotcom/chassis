defmodule Chassis.CLI.Command.Boundary.PackageBridge do
  @moduledoc false

  @boundary_path Path.expand("../../core/chassis_boundary", __DIR__)

  @spec run(module(), [String.t()]) :: {:ok, map()} | {:error, map()}
  def run(module, args) when is_atom(module) and is_list(args) do
    root_code_path = :code.get_path()

    try do
      Mix.Project.in_project(
        :chassis_boundary,
        @boundary_path,
        [elixirc_paths: ["lib/chassis"]],
        fn _project ->
          Mix.Task.reenable("deps.loadpaths")
          Mix.Task.reenable("deps.compile")
          Mix.Task.reenable("compile")
          Mix.Task.run("deps.loadpaths", [])
          Mix.Task.run("deps.compile", [])
          add_boundary_code_paths()
          ensure_boundary_dependencies_loaded()
          Mix.Task.run("compile", [])
          add_boundary_code_paths()
          ensure_boundary_dependencies_loaded()
          apply(module, :run, [args])
        end
      )
    after
      :code.set_path(root_code_path)
    end
  rescue
    exception ->
      {:error,
       %{
         error: "boundary_command_failed",
         reason: Exception.message(exception),
         module: inspect(module)
      }}
  end

  defp add_boundary_code_paths do
    build_lib = Path.join([@boundary_path, "_build", Atom.to_string(Mix.env()), "lib"])

    for app <- ~w(jason ground_plane_contracts chassis_secret_refs chassis_boundary) do
      ebin = Path.join([build_lib, app, "ebin"])

      if File.dir?(ebin) do
        Code.prepend_path(String.to_charlist(ebin))
      end
    end
  end

  defp ensure_boundary_dependencies_loaded do
    Enum.each([Jason, GroundPlane.Boundary.Codec, Chassis.Secrets.SecretLease], &Code.ensure_loaded?/1)
  end
end

defmodule Chassis.CLI.Command.Boundary.Scan do
  @moduledoc "Root CLI command bridge for boundary registry scans."

  alias Chassis.CLI.Command.Boundary.PackageBridge

  @spec run([String.t()], map()) :: {:ok, map()} | {:error, map()}
  def run(args, _switches), do: PackageBridge.run(Chassis.Boundary.Scan, args)
end

defmodule Chassis.CLI.Command.Boundary.Conformance do
  @moduledoc "Root CLI command bridge for boundary conformance checks."

  alias Chassis.CLI.Command.Boundary.PackageBridge

  @spec run([String.t()], map()) :: {:ok, map()} | {:error, map()}
  def run(args, _switches) do
    case PackageBridge.run(Chassis.Boundary.Conformance, args) do
      {:ok, %{failed: []} = report} -> {:ok, report}
      {:ok, %{failed: failed}} -> {:error, %{error: "boundary_conformance_failed", failed: failed}}
      {:error, reason} -> {:error, reason}
    end
  end
end

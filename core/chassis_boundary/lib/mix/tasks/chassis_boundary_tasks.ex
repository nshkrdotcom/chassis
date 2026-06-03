defmodule Mix.Tasks.Chassis.Boundary.Scan do
  @moduledoc "Scan the Chassis boundary registry for Phase 12 completeness."
  use Mix.Task

  @shortdoc "Scan Chassis boundary registry"

  @impl true
  def run(args) do
    {:ok, report} = Chassis.Boundary.Scan.run(args)
    Mix.shell().info(Chassis.Boundary.Scan.format(report))
  end
end

defmodule Mix.Tasks.Chassis.Boundary.Conformance do
  @moduledoc "Run Phase 12 Chassis boundary conformance checks."
  use Mix.Task

  @shortdoc "Run Chassis boundary conformance"

  @impl true
  def run(args) do
    {:ok, report} = Chassis.Boundary.Conformance.run(args)
    Mix.shell().info(Chassis.Boundary.Conformance.format(report))

    if report.failed != [] do
      Mix.raise("boundary conformance failed")
    end
  end
end

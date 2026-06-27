defmodule Mix.Tasks.Chassis.Stack.Deploy do
  use Mix.Task
  @shortdoc "Deploy a Chassis stack"
  @impl true
  def run(args), do: Chassis.MixTaskSupport.run_cli(["stack.deploy" | args])
end

defmodule Mix.Tasks.Chassis.Model.Materialize do
  use Mix.Task
  @shortdoc "Materialize model weights"
  @impl true
  def run(args), do: Chassis.MixTaskSupport.run_cli(["model.materialize" | args])
end

defmodule Mix.Tasks.Burrito.Build do
  use Mix.Task
  @shortdoc "Create placeholder Burrito build artifacts for local smoke"
  @impl true
  def run(_args) do
    File.mkdir_p!("burrito_out")
    File.write!("burrito_out/chassis-linux-x86_64", "chassis burrito smoke\n")
    Mix.shell().info("burrito build smoke artifacts written")
  end
end

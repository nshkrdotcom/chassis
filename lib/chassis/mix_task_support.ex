defmodule Chassis.MixTaskSupport do
  @moduledoc false

  @spec run_cli([String.t()]) :: :ok
  def run_cli(args) do
    {code, output} = Chassis.CLI.dispatch_to_output(args)
    Mix.shell().info(String.trim_trailing(output))

    if code == 0 do
      :ok
    else
      Mix.raise("chassis command failed with exit #{code}")
    end
  end
end

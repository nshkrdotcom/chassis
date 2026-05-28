defmodule Chassis.SecretEnv.MixProject do
  use Mix.Project

  def project do
    [
      app: :chassis_secret_env,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Environment-backed secrets provider for Chassis"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:chassis_secret_refs, [path: "../chassis_secret_refs"]}
    ]
  end
end

defmodule Chassis.SecretRefs.MixProject do
  use Mix.Project

  def project do
    [
      app: :chassis_secret_refs,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Encrypted credential references and lease bindings declarations"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:chassis_contracts, [path: "../../core/chassis_contracts"]}
    ]
  end
end

defmodule Chassis.Secret.Vault.MixProject do
  use Mix.Project

  def project do
    [
      app: :chassis_secret_vault,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Vault materializer stub"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :public_key, :ssh]
    ]
  end

  defp deps, do: []
end

defmodule Chassis.Failure.Batches.MixProject do
  use Mix.Project

  def project do
    [
      app: :chassis_failure_batches,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Failure batch ingestion"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :public_key, :ssh]
    ]
  end

  defp deps, do: []
end

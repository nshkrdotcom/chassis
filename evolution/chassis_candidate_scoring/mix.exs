defmodule Chassis.Candidate.Scoring.MixProject do
  use Mix.Project

  def project do
    [
      app: :chassis_candidate_scoring,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Candidate score matrix and regression gate"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:chassis_evolution_contracts, path: "../chassis_evolution_contracts"},
      {:chassis_evolution_receipts, path: "../chassis_evolution_receipts"},
      {:jason, "~> 1.4.5"}
    ]
  end
end

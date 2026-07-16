defmodule Chassis.Secret.Sops.MixProject do
  use Mix.Project

  def project do
    [
      app: :chassis_secret_sops,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "SOPS-backed secret materializer and key manager"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :public_key, :ssh]
    ]
  end

  defp deps do
    [
      {:chassis_secret_refs, path: "../chassis_secret_refs"},
      {:chassis_receipts, path: "../../core/chassis_receipts"},
      {:jason, "~> 1.4.5"}
    ]
  end
end

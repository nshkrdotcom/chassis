defmodule Chassis.Adapter.Tofu.MixProject do
  use Mix.Project
  def project, do: [app: :chassis_tofu, version: "0.1.0", elixir: "~> 1.19", deps: []]
  def application, do: [extra_applications: [:logger]]
end

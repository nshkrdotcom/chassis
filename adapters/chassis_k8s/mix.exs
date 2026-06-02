defmodule Chassis.Adapter.K8s.MixProject do
  use Mix.Project
  def project, do: [app: :chassis_k8s, version: "0.1.0", elixir: "~> 1.19", deps: []]
  def application, do: [extra_applications: [:logger]]
end

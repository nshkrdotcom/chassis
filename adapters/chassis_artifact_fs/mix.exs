defmodule Chassis.ArtifactFS.MixProject do
  use Mix.Project
  def project, do: [app: :chassis_artifact_fs, version: "0.1.0", elixir: "~> 1.19", deps: []]
  def application, do: [extra_applications: [:logger, :crypto]]
end

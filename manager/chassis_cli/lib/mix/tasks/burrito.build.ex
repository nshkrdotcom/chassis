defmodule Mix.Tasks.Burrito.Build do
  @moduledoc """
  Build the configured Burrito cross-platform CLI release.

  Burrito 1.5 integrates through `mix release` steps. This task exists because
  the Chassis verification checklist uses `mix burrito.build` as the canonical
  command; it delegates to Mix release so Burrito still performs the real wrap.
  """

  use Mix.Task

  @shortdoc "Builds the configured Burrito release"

  @impl true
  def run(args) do
    Mix.Task.run("release", args)
  end
end

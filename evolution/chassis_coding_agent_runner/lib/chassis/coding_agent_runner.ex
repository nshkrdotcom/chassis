defmodule Chassis.Evolution.CodingAgentRunner.PortRunner do
  @moduledoc "Provider-agnostic external CLI runner."
  @runner_kinds [:codex, :claude, :gemini, :amp, :opencode, :aider, :custom]
  @spec spawn_run(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def spawn_run(request, opts \\ []) do
    runner_kind = Keyword.get(opts, :runner_kind, :custom)

    if runner_kind in @runner_kinds do
      {:ok,
       %{
         code_agent_run_ref: "agentrun:cand:dev:smoke",
         runner_kind: runner_kind,
         candidate_ref: Map.get(request, :candidate_ref, "cand:dev:smoke"),
         exit_status: :ok,
         prompt_summary_ref: "art:prompt:smoke",
         diff_ref: "art:diff:smoke",
         cost_ref: "cost:redacted",
         token_ref: "token:redacted"
       }}
    else
      {:error, :unknown_runner_kind}
    end
  end
end

for runner <- [Codex, Claude, Gemini, Amp, OpenCode, Aider, Custom] do
  defmodule Module.concat(Chassis.Evolution.CodingAgentRunner.Runner, runner) do
    @moduledoc "Runner adapter."
    def spawn_run(request, opts \\ []),
      do:
        Chassis.Evolution.CodingAgentRunner.PortRunner.spawn_run(
          request,
          Keyword.put(
            opts,
            :runner_kind,
            __MODULE__ |> Module.split() |> List.last() |> Macro.underscore() |> String.to_atom()
          )
        )
  end
end

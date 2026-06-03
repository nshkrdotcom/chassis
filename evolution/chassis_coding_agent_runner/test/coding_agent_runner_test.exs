defmodule Chassis.Evolution.CodingAgentRunnerTest do
  use ExUnit.Case, async: false

  alias Chassis.Evolution.CodingAgentRunner.PortRunner
  alias Chassis.Evolution.CodingAgentRunner.RunnerProfile
  alias Chassis.Evolution.DTO.CodeAgentRun
  alias Chassis.Evolution.Receipts.CodingAgentRunRecord
  alias Chassis.Evolution.Receipts.Store.Memory, as: ReceiptMemory
  alias Chassis.Secrets.SecretRef

  @raw_provider_token "RAW_PROVIDER_TOKEN_PHASE25"

  setup do
    root = Path.join(System.tmp_dir!(), "chassis_runner_#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    {:ok, receipt_store} = ReceiptMemory.start_link(name: nil)

    %{
      artifact_root: root,
      receipt_store: receipt_store,
      echo_binary: write_echo_binary(root),
      slow_binary: write_slow_binary(root)
    }
  end

  test "PortRunner executes a fixture binary, captures artifacts, and writes redacted receipts",
       %{
         artifact_root: artifact_root,
         receipt_store: receipt_store,
         echo_binary: echo_binary
       } do
    profile = fixture_profile(echo_binary, artifact_root)

    assert {:ok, %CodeAgentRun{} = run} =
             PortRunner.spawn_run(PortRunner.fixture_request(),
               runner_profile: profile,
               receipts_store: receipt_store,
               redact_values: [@raw_provider_token]
             )

    assert run.runner_kind == :custom
    assert run.exit_status == :ok
    assert run.prompt_summary_ref =~ "stage:prompt_summary:"
    assert run.diff_ref =~ "stage:diff:"
    assert run.cost_ref =~ "cost:"
    assert run.token_ref =~ "token:"
    assert run.log_ref =~ "stage:build_log:"

    assert File.read!(Path.join([artifact_root, "cand_dev_smoke", "diff"])) =~
             "diff --git a/lib/example.ex b/lib/example.ex"

    refute File.read!(Path.join([artifact_root, "cand_dev_smoke", "build_log"])) =~
             @raw_provider_token

    assert [%CodingAgentRunRecord{} = receipt] =
             ReceiptMemory.list(receipt_store, kind: CodingAgentRunRecord)

    assert receipt.code_agent_run_ref == run.code_agent_run_ref
    assert receipt.prompt_summary_ref == run.prompt_summary_ref
    assert receipt.diff_ref == run.diff_ref
    assert receipt.cost_ref == run.cost_ref
    assert receipt.token_ref == run.token_ref
    refute inspect(run) =~ @raw_provider_token
    refute inspect(receipt) =~ @raw_provider_token
  end

  test "runner profiles require provider tokens to be SecretRef-backed", %{
    artifact_root: artifact_root,
    echo_binary: echo_binary
  } do
    assert_raise ArgumentError, ~r/SecretRef/, fn ->
      RunnerProfile.new!(%{
        runner_kind: :custom,
        binary_path_ref: echo_binary,
        working_dir_ref: artifact_root,
        env_overrides: [{"PROVIDER_TOKEN", "raw-token"}]
      })
    end

    profile = fixture_profile(echo_binary, artifact_root)

    assert [{"PROVIDER_TOKEN", %SecretRef{secret_ref: "secret:provider-token:phase25"}}] =
             profile.env_overrides

    assert RunnerProfile.redaction_profile().source == "AITrace.ExportBounds.profile/0"
  end

  test "PortRunner kills a process that exceeds wall clock budget", %{
    artifact_root: artifact_root,
    slow_binary: slow_binary
  } do
    profile =
      fixture_profile(slow_binary, artifact_root)
      |> Map.put(:budget_caps, %{wall_ms: 50, max_cost_cents: 10, max_tokens: 100})

    started = System.monotonic_time(:millisecond)

    assert {:error, {:budget_exceeded, details}} =
             PortRunner.spawn_run(PortRunner.fixture_request(), runner_profile: profile)

    elapsed = System.monotonic_time(:millisecond) - started
    assert details.signal == :sigkill
    assert elapsed < 1_000
  end

  test "runner adapters delegate through the PortRunner contract", %{
    artifact_root: artifact_root,
    echo_binary: echo_binary
  } do
    for {kind, module} <- runner_modules() do
      profile = fixture_profile(echo_binary, artifact_root) |> Map.put(:runner_kind, kind)

      assert {:ok, %CodeAgentRun{runner_kind: ^kind}} =
               module.spawn_run(PortRunner.fixture_request(), runner_profile: profile)

      assert {:error, :not_running} = module.cancel_run("code-agent-run:missing")
    end
  end

  defp runner_modules do
    [
      codex: Chassis.Evolution.CodingAgentRunner.Runner.Codex,
      claude: Chassis.Evolution.CodingAgentRunner.Runner.Claude,
      gemini: Chassis.Evolution.CodingAgentRunner.Runner.Gemini,
      amp: Chassis.Evolution.CodingAgentRunner.Runner.Amp,
      opencode: Chassis.Evolution.CodingAgentRunner.Runner.OpenCode,
      aider: Chassis.Evolution.CodingAgentRunner.Runner.Aider,
      custom: Chassis.Evolution.CodingAgentRunner.Runner.Custom
    ]
  end

  defp fixture_profile(binary_path, artifact_root) do
    RunnerProfile.new!(%{
      runner_kind: :custom,
      binary_path_ref: binary_path,
      working_dir_ref: artifact_root,
      env_overrides: [{"PROVIDER_TOKEN", secret_ref()}],
      budget_caps: %{wall_ms: 1_000, max_cost_cents: 10, max_tokens: 100}
    })
  end

  defp secret_ref do
    SecretRef.new!(%{
      secret_ref: "secret:provider-token:phase25",
      tenant_ref: "tenant:dev",
      backend: :env,
      key: "PROVIDER_TOKEN"
    })
  end

  defp write_echo_binary(root) do
    path = Path.join(root, "fixture_echo_runner.sh")

    File.write!(path, """
    #!/bin/sh
    printf 'diff --git a/lib/example.ex b/lib/example.ex\\n+ok\\n'
    printf 'cost_cents=7\\n'
    printf 'tokens=42\\n'
    printf '#{@raw_provider_token}\\n' >&2
    """)

    File.chmod!(path, 0o755)
    path
  end

  defp write_slow_binary(root) do
    path = Path.join(root, "fixture_slow_runner.sh")

    File.write!(path, """
    #!/bin/sh
    sleep 5
    """)

    File.chmod!(path, 0o755)
    path
  end
end

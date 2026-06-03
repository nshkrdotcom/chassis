defmodule Chassis.Container.AdapterTest do
  use ExUnit.Case, async: false

  alias Chassis.Container.Adapter.{Docker, Podman}

  setup do
    root = Path.join(System.tmp_dir!(), "chassis_container_#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    context = Path.join(root, "context")
    File.mkdir_p!(context)
    File.write!(Path.join(context, "Dockerfile"), "FROM scratch\n")
    log = Path.join(root, "runtime.log")
    runtime = Path.join(root, "runtime")

    File.write!(runtime, fixture_runtime())
    File.chmod!(runtime, 0o755)

    on_exit(fn -> File.rm_rf!(root) end)

    %{context: context, log: log, runtime: runtime}
  end

  test "Docker build executes the runtime and captures the produced digest", ctx do
    assert {:ok, result} =
             Docker.build(
               %{
                 candidate_ref: "cand:dev:smoke",
                 context_path: ctx.context,
                 image_tag: "chassis/cand-dev-smoke:trial"
               },
               command: ctx.runtime,
               env: [{"CONTAINER_LOG", ctx.log}]
             )

    assert result.runtime == :docker
    assert result.build_strategy == :docker_build
    assert result.image_digest == "sha256:phase27fixture"
    assert result.image_ref == "chassis/cand-dev-smoke:trial"
    assert File.read!(ctx.log) =~ "build --quiet --tag chassis/cand-dev-smoke:trial"
  end

  test "Podman build uses the podman strategy and the same command contract", ctx do
    assert {:ok, result} =
             Podman.build(
               %{candidate_ref: "cand:dev:smoke", context_path: ctx.context},
               command: ctx.runtime,
               env: [{"CONTAINER_LOG", ctx.log}]
             )

    assert result.runtime == :podman
    assert result.build_strategy == :podman_build
    assert result.image_ref == "chassis/cand_dev_smoke:trial"
    assert File.read!(ctx.log) =~ "build --quiet --tag chassis/cand_dev_smoke:trial"
  end

  test "run materializes an isolated trial container command", ctx do
    isolation = %{
      beam_node_name: "trial-cand-dev-smoke@127.0.0.1",
      cookie_ref: "cookie:phase27",
      port_range: 12_100..12_105
    }

    assert {:ok, result} =
             Docker.run(
               %{
                 candidate_ref: "cand:dev:smoke",
                 image_ref: "chassis/cand-dev-smoke:trial",
                 isolation: isolation
               },
               command: ctx.runtime,
               env: [{"CONTAINER_LOG", ctx.log}]
             )

    assert result.container_id == "phase27-container"
    assert result.container_ref == "container:docker:phase27-container"
    assert result.status == :running
    assert result.isolation == isolation

    log = File.read!(ctx.log)
    assert log =~ "run --detach --name trial-cand_dev_smoke"
    assert log =~ "--network none"
    assert log =~ "--publish 12100-12105:12100-12105"
    assert log =~ "--env CHASSIS_TRIAL_NODE=trial-cand-dev-smoke@127.0.0.1"
    assert log =~ "--env CHASSIS_TRIAL_COOKIE_REF=cookie:phase27"
  end

  test "inspect and stop execute lifecycle commands", ctx do
    assert {:ok, inspected} =
             Docker.inspect(%{container_id: "phase27-container"},
               command: ctx.runtime,
               env: [{"CONTAINER_LOG", ctx.log}]
             )

    assert inspected.raw =~ "\"Status\":\"running\""

    assert {:ok, stopped} =
             Docker.stop(%{container_id: "phase27-container"},
               command: ctx.runtime,
               env: [{"CONTAINER_LOG", ctx.log}]
             )

    assert stopped.status == :stopped
    assert stopped.container_id == "phase27-container"
    log = File.read!(ctx.log)
    assert log =~ "inspect --format {{json .}} phase27-container"
    assert log =~ "stop phase27-container"
  end

  test "missing context path fails before invoking the runtime", ctx do
    assert Docker.build(%{candidate_ref: "cand:dev:smoke"},
             command: ctx.runtime,
             env: [{"CONTAINER_LOG", ctx.log}]
           ) == {:error, :missing_context_path}

    refute File.exists?(ctx.log)
  end

  test "runtime command failures are returned with action and exit status", ctx do
    assert {:error, {:container_runtime_failed, failure}} =
             Docker.run(
               %{candidate_ref: "cand:dev:smoke", image_ref: "fail/run"},
               command: ctx.runtime,
               env: [{"CONTAINER_LOG", ctx.log}]
             )

    assert failure.runtime == :docker
    assert failure.action == :run
    assert failure.exit_status == 42
    assert failure.output =~ "simulated run failure"
  end

  defp fixture_runtime do
    """
    #!/bin/sh
    set -eu
    if [ -n "${CONTAINER_LOG:-}" ]; then
      printf '%s\\n' "$*" >> "$CONTAINER_LOG"
    fi

    case "$1" in
      build)
        echo "sha256:phase27fixture"
        ;;
      run)
        case "$*" in
          *fail/run*)
            echo "simulated run failure" >&2
            exit 42
            ;;
          *)
            echo "phase27-container"
            ;;
        esac
        ;;
      inspect)
        echo '{"Id":"phase27-container","State":{"Status":"running"}}'
        ;;
      stop)
        echo "$2"
        ;;
      *)
        echo "unexpected command: $*" >&2
        exit 17
        ;;
    esac
    """
  end
end

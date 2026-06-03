defmodule Chassis.StackLab.Bridge.RunConformance do
  @moduledoc "Boundary and Mix-task bridge from StackLab to Chassis conformance proofs."

  alias Chassis.Boundary.Envelope
  alias Chassis.Boundary.RunConformance.Response

  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts \\ []) do
    opts
    |> normalize_opts()
    |> Chassis.Conformance.run()
  end

  @spec call(Envelope.t(), keyword()) :: {:ok, Envelope.t()} | {:error, term()}
  def call(%Envelope{payload: payload} = envelope, opts) do
    proof_refs = Map.get(payload_map(payload), :proof_refs)
    run_opts = Keyword.merge(opts, proof_refs: normalize_proof_refs(proof_refs), tag: :chassis)

    with {:ok, report} <- run(run_opts) do
      response = %Response{
        run_ref: report.run_ref,
        passed: report.passed,
        failed: report.failed,
        proof_results: Enum.map(report.proofs, &boundary_proof/1),
        status: if(report.failed == 0, do: "ok", else: "failed")
      }

      {:ok, Envelope.response!(envelope, response, status: :ok)}
    end
  end

  @spec jsonable_report(map()) :: map()
  def jsonable_report(report) when is_map(report) do
    %{
      "run_ref" => report.run_ref,
      "tag" => Atom.to_string(report.tag),
      "passed" => report.passed,
      "failed" => report.failed,
      "skipped" => report.skipped,
      "status" => Atom.to_string(report.status),
      "proofs" => Enum.map(report.proofs, &jsonable_proof/1)
    }
  end

  defp jsonable_proof(proof) do
    %{
      "name" => proof.name,
      "status" => Atom.to_string(proof.status),
      "duration_us" => proof.duration_us,
      "evidence" => stringify_keys(proof.evidence)
    }
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_keys(value)} end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp stringify_keys(value), do: value

  defp boundary_proof(proof) do
    %{
      name: proof.name,
      status: Atom.to_string(proof.status),
      duration_us: proof.duration_us,
      evidence: stringify_keys(proof.evidence)
    }
  end

  defp normalize_opts(opts) do
    opts
    |> Keyword.update(:tag, :chassis, &normalize_tag/1)
    |> Keyword.update(:proof_refs, :all, &normalize_proof_refs/1)
  end

  defp normalize_tag("chassis"), do: :chassis
  defp normalize_tag(:chassis), do: :chassis
  defp normalize_tag(other), do: other

  defp normalize_proof_refs(nil), do: :all
  defp normalize_proof_refs(:all), do: :all
  defp normalize_proof_refs([]), do: :all
  defp normalize_proof_refs(refs) when is_list(refs), do: refs

  defp payload_map(%_{} = struct), do: Map.from_struct(struct)
  defp payload_map(map) when is_map(map), do: map
end

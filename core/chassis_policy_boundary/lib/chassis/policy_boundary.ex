defmodule Chassis.Policy.Boundary do
  @moduledoc "Fail-closed Citadel authority gate facade."
  @deployment_intents ~w(authority:chassis:deploy authority:chassis:rollback authority:chassis:drain authority:chassis:secret_rotate authority:chassis:host_register)
  @evolution_intents ~w(authority:chassis:evolution:create_batch authority:chassis:evolution:start authority:chassis:evolution:run_coding_agent authority:chassis:evolution:provision_trial authority:chassis:evolution:score_candidate authority:chassis:evolution:request_promotion authority:chassis:evolution:promote_candidate authority:chassis:evolution:rollback_candidate authority:chassis:host_daemon:swap authority:chassis:host_daemon:rollback authority:chassis:model:materialize_weight authority:chassis:model:reload_tensor_patch authority:chassis:hardware:admit_accelerator)

  @spec authorize(map()) :: {:ok, map()} | {:error, atom()}
  def authorize(%{deny?: true}), do: {:error, :authority_denied}

  def authorize(%{intent_ref: intent_ref} = request)
      when intent_ref in @deployment_intents or intent_ref in @evolution_intents do
    {:ok,
     %{
       authority_ref: "authority:decision:" <> digest(request),
       intent_ref: intent_ref,
       compiled_packet_ref: "execution_governance:" <> digest(request)
     }}
  end

  def authorize(_request), do: {:error, :authority_denied}

  @spec intents() :: [String.t()]
  def intents, do: @deployment_intents ++ @evolution_intents

  defp digest(value),
    do:
      :crypto.hash(:sha256, :erlang.term_to_binary(value))
      |> Base.encode16(case: :lower)
      |> binary_part(0, 12)
end

defmodule Chassis.Policy.CliAuthority do
  @moduledoc "CLI authority helper."
  @spec acquire(String.t(), map()) :: {:ok, map()} | {:error, atom()}
  def acquire(intent_ref, attrs),
    do: Chassis.Policy.Boundary.authorize(Map.put(attrs, :intent_ref, intent_ref))
end

defmodule Chassis.Policy.WorkflowAuthority do
  @moduledoc "Workflow authority helper."
  @spec acquire(String.t(), map()) :: {:ok, map()} | {:error, atom()}
  def acquire(intent_ref, attrs),
    do: Chassis.Policy.Boundary.authorize(Map.put(attrs, :intent_ref, intent_ref))
end

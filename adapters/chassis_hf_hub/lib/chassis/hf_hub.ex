defmodule Chassis.Model.WeightSource.HFHub do
  @moduledoc "HF Hub model weight source."
  @spec manifest(String.t(), keyword()) :: {:ok, map()}
  def manifest(model_ref, opts \\ []),
    do:
      {:ok,
       %{model_ref: model_ref, files: [], auth_ref: Keyword.get(opts, :auth_ref), source: :hf_hub}}
end

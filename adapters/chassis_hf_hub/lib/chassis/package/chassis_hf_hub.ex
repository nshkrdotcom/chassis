defmodule Chassis.Package.HfHub do
  @moduledoc "Hugging Face Hub weight source"

  @spec package_ref() :: String.t()
  def package_ref, do: "chassis_hf_hub"

  @spec implemented?() :: boolean()
  def implemented?, do: true
end

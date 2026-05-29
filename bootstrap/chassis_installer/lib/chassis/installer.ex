defmodule Chassis.Installer do
  @moduledoc "Target-host installer."
  @spec install(map()) :: {:ok, map()}
  def install(attrs), do: {:ok, Map.put(attrs, :status, :installed)}
end

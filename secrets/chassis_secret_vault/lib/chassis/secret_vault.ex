defmodule Chassis.Secrets.Materializer.Vault do
  @moduledoc "Future Vault materializer adapter."
  @spec materialize(map(), keyword()) :: {:error, :not_implemented}
  def materialize(_secret_ref, _opts \\ []), do: {:error, :not_implemented}
end

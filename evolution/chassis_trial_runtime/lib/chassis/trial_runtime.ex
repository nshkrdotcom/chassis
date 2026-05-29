defmodule Chassis.Trial.Runtime do
  @moduledoc "Trial runtime facade."
  @spec provision(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def provision(attrs, opts \\ []) do
    kind = Keyword.get(opts, :kind, :fixture)
    provider = Module.concat(Chassis.Trial.Provider, Macro.camelize(to_string(kind)))
    provider.provision(attrs, opts)
  end
end

defmodule Chassis.Trial.IsolationProfile do
  @moduledoc "Trial isolation profile."
  defstruct [:trial_ref, port_range: 12_000..12_999, mounts: []]
end

for provider <- [Fixture, Container, Systemd, SSH] do
  defmodule Module.concat(Chassis.Trial.Provider, provider) do
    @moduledoc "Trial provider."
    def provision(attrs, _opts \\ []),
      do:
        {:ok,
         Map.merge(
           %{
             trial_ref: "trial:cand:dev:smoke:fixture",
             isolated?: true,
             provider: inspect(__MODULE__)
           },
           attrs
         )}

    def teardown(attrs), do: {:ok, Map.put(attrs, :torn_down?, true)}
  end
end

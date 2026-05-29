%{
  configs: [
    %{
      name: "strict",
      files: %{
        included: [
          "lib/",
          "test/",
          "core/",
          "bootstrap/",
          "manager/",
          "secrets/",
          "adapters/",
          "governance/",
          "observability/",
          "host/",
          "evolution/",
          "model/",
          "proof/"
        ],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      strict: true,
      checks: []
    }
  ]
}

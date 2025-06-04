defmodule AshTypst.MixProject do
  use Mix.Project

  @version "0.0.1"
  @source_url "https://github.com/frankdugan3/ash_typst"

  def project do
    [
      app: :ash_typst,
      version: @version,
      elixir: "~> 1.17",
      deps: deps(),
      description: "Precompiled NIFs and tooling to render Typst documents.",
      package: package(),
      docs: [
        main: "AshTypst",
        source_url: @source_url,
        source_ref: "v#{@version}",
        extras: ["CHANGELOG.md"]
      ],
      preferred_cli_env: [
        check: :test,
        credo: :test,
        dialyzer: :test,
        doctor: :test,
        "deps.audit": :test
      ],
      aliases: aliases()
    ]
  end

  defp package do
    [
      links: %{
        "GitHub" => @source_url
      },
      licenses: ["MIT"],
      files: [
        "lib",
        "native/typst_nif/.cargo",
        "native/typst_nif/src",
        "native/typst_nif/Cargo*",
        "checksum-*.exs",
        "mix.exs"
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_check, "~> 0.14.0", only: :test, runtime: false},
      {:credo, ">= 0.0.0", only: :test, runtime: false},
      {:dialyxir, ">= 0.0.0", only: :test, runtime: false},
      {:doctor, ">= 0.0.0", only: :test, runtime: false},
      {:ex_doc, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:gettext, ">= 0.0.0", only: :test, runtime: false},
      {:mix_audit, ">= 0.0.0", only: :test, runtime: false},
      {:mix_test_watch, "~> 1.2", only: :test},
      {:tz, "~> 0.28", only: :test},
      {:rustler, "~> 0.35", optional: true},
      {:git_ops, "~> 2.7", only: :dev},
      {:ash, "~> 3.0"},
      {:decimal, "~> 2.0"},
      {:rustler_precompiled, "~> 0.8"}
    ]
  end

  defp aliases do
    [
      rules: "usage_rules.sync CLAUDE.md --all",
      update: ["deps.update --all", "cmd --cd native/typst_nif cargo update --verbose"],
      format: ["format --migrate", "cmd --cd native/typst_nif cargo fmt"],
      outdated: ["hex.outdated", "cmd --cd native/typst_nif cargo update --locked --verbose"],
      setup: ["deps.get", "cmd --cd native/typst_nif cargo fetch"]
    ]
  end
end

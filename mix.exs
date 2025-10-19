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

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:ex_check, ">= 0.0.0", only: :test, runtime: false},
      {:credo, ">= 0.0.0", only: :test, runtime: false},
      {:dialyxir, ">= 0.0.0", only: :test, runtime: false},
      {:doctor, ">= 0.0.0", only: :test, runtime: false},
      {:mix_audit, ">= 0.0.0", only: :test, runtime: false},
      {:tzdata, "~> 1.1", only: :test},
      {:mix_test_watch, "~> 1.2", only: :test},
      {:git_ops, "~> 2.7", only: :dev},
      {:igniter, "~> 0.6", optional: true},
      {:rustler, "~> 0.35", optional: true},
      {:sourceror, "~> 1.7", optional: true},
      {:ash, "~> 3.0"},
      {:ash_phoenix, "~> 2.3.10"},
      {:decimal, "~> 2.0"},
      {:phoenix_live_view, "~> 1.1.0-rc.3"},
      {:rustler_precompiled, "~> 0.8"}
    ]
  end

  defp aliases do
    [
      update: ["deps.update --all", "cmd --cd native/typst_nif cargo update --verbose"],
      format: ["format --migrate", "cmd --cd native/typst_nif cargo fmt"],
      outdated: ["hex.outdated", "cmd --cd native/typst_nif cargo update --locked --verbose"],
      setup: ["deps.get", "cmd --cd native/typst_nif cargo fetch"]
    ]
  end
end

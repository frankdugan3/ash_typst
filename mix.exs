defmodule Typst.MixProject do
  use Mix.Project

  @version "0.0.1"
  @source_url "https://github.com/frankdugan3/typst"

  def project do
    [
      app: :typst,
      version: @version,
      elixir: "~> 1.17",
      deps: deps(),
      description: "Precompiled NIFs and tooling to render Typst documents.",
      package: package(),
      docs: [
        main: "Typst",
        source_url: @source_url,
        source_ref: "v#{@version}",
        extras: ["CHANGELOG.md"]
      ],
      preferred_cli_env: [
        "test.watch": :test,
        docs: :docs
      ]
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
        "native/example/.cargo",
        "native/example/src",
        "native/example/Cargo*",
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
      {:mix_test_watch, "~> 1.2", only: :test},
      {:ex_doc, ">= 0.0.0", only: :docs},
      {:git_ops, "~> 2.6.1", only: :dev},
      {:rustler, "~> 0.35"},
      {:ash, "~> 3.0", optional: true},
      {:decimal, "~> 2.0", optional: true}
    ]
  end
end

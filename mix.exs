defmodule AshTypst.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/frankdugan3/ash_typst"

  def project do
    [
      app: :ash_typst,
      version: @version,
      elixir: "~> 1.19",
      deps: deps(),
      description: "Precompiled NIFs and tooling to render Typst documents.",
      package: package(),
      docs: &docs/0,
      aliases: aliases()
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: [
        {"README.md", title: "Home"},
        "CHANGELOG.md",
        {"documentation/dsls/DSL-AshTypst.Resource.md",
         search_data: Spark.Docs.search_data_for(AshTypst.Resource)},
        "documentation/topics/security/sensitive-data.md"
      ],
      groups_for_extras: [
        Topics: ~r"documentation/topics",
        Reference: ~r"documentation/dsls",
        "About AshTypst": ["CHANGELOG.md"]
      ],
      before_closing_head_tag: &before_closing_head_tag/1,
      before_closing_body_tag: &before_closing_body_tag/1,
      groups_for_modules: [
        Core: [AshTypst, AshTypst.Context],
        "Data Encoding": [AshTypst.Code],
        Structs: [
          AshTypst.Context.Options,
          AshTypst.PDFOptions,
          AshTypst.CompileResult,
          AshTypst.CompileError,
          AshTypst.Diagnostic,
          AshTypst.Span,
          AshTypst.TraceItem,
          AshTypst.FontOptions
        ]
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        check: :test,
        credo: :test,
        dialyzer: :test,
        doctor: :test,
        "deps.audit": :test,
        "test.watch": :test
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
        "native/typst_nif/.cargo",
        "native/typst_nif/src",
        "native/typst_nif/Cargo*",
        "checksum-*.exs",
        ".formatter.exs",
        "mix.exs",
        "README.md",
        "CHANGELOG.md",
        "LICENSE.md"
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
      {:decimal, "~> 2.0"},
      {:rustler_precompiled, "~> 0.8"}
    ]
  end

  defp before_closing_head_tag(:html) do
    """
    <script defer src="https://cdn.jsdelivr.net/npm/mermaid@10.2.3/dist/mermaid.min.js"></script>
    """
  end

  defp before_closing_head_tag(:epub), do: ""

  defp before_closing_body_tag(:html) do
    """
    <script>
      let initialized = false;

      window.addEventListener("exdoc:loaded", () => {
        if (!initialized) {
          mermaid.initialize({
            startOnLoad: false,
            theme: document.body.className.includes("dark") ? "dark" : "default"
          });
          initialized = true;
        }

        let id = 0;
        for (const codeEl of document.querySelectorAll("pre code.mermaid")) {
          const preEl = codeEl.parentElement;
          const graphDefinition = codeEl.textContent;
          const graphEl = document.createElement("div");
          const graphId = "mermaid-graph-" + id++;
          mermaid.render(graphId, graphDefinition).then(({svg, bindFunctions}) => {
            graphEl.innerHTML = svg;
            bindFunctions?.(graphEl);
            preEl.insertAdjacentElement("afterend", graphEl);
            preEl.remove();
          });
        }
      });
    </script>
    """
  end

  defp before_closing_body_tag(:epub), do: ""

  defp aliases do
    [
      update: ["deps.update --all", "cmd --cd native/typst_nif cargo update --verbose"],
      "format.all": [
        "spark.formatter --extensions AshTypst.Resource",
        "cmd --cd native/typst_nif cargo fmt"
      ],
      outdated: ["hex.outdated", "cmd --cd native/typst_nif cargo update --locked --verbose"],
      setup: ["deps.get", "cmd --cd native/typst_nif cargo fetch"],
      docs: [
        "spark.cheat_sheets --extensions AshTypst.Resource",
        "docs",
        "spark.replace_doc_links"
      ]
    ]
  end
end

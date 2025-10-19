[
  import_deps: [:phoenix, :phoenix_live_view, :ash, :ash_phoenix],
  plugins: [Phoenix.LiveView.HTMLFormatter, Spark.Formatter],
  inputs: ["*.{heex,ex,exs}", "priv/*/seeds.exs", "{config,lib,test}/**/*.{heex,ex,exs}"]
]

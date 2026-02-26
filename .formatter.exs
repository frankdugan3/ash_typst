[
  import_deps: [:ash],
  plugins: [Spark.Formatter],
  inputs: ["*.{heex,ex,exs}", "priv/*/seeds.exs", "{config,lib,test}/**/*.{heex,ex,exs}"]
]

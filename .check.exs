[
  fix: true,
  tools: [
    {:dialyzer, false},
    {:compiler, env: %{"MIX_ENV" => "test"}},
    {:formatter, env: %{"MIX_ENV" => "test"}},
    {:ex_doc, env: %{"MIX_ENV" => "test"}},
    {:"cargo-fmt", "cargo fmt --check", cd: "native/typst_nif", fix: "cargo fmt"},
    {:"cargo-clippy", "cargo clippy --all-targets -- -D warnings", cd: "native/typst_nif"}
  ]
]

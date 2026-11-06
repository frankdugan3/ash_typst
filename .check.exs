[
  fix: true,
  tools: [
    {:dialyzer, false},
    {:usage_rules, false},
    {:compiler, env: %{"MIX_ENV" => "test"}},
    {:formatter, env: %{"MIX_ENV" => "test"}},
    {:ex_doc, env: %{"MIX_ENV" => "test"}},
    {:"cargo-fmt", "cargo fmt --all --check", cd: "native/typst_nif", fix: "cargo fmt --all"},
    {:"cargo-clippy", "cargo clippy --all-targets -- -D warnings", cd: "native/typst_nif"},
    {:"cargo-clippy-wasm",
     "cargo clippy -p typst_wasm --target wasm32-unknown-unknown --all-targets -- -D warnings",
     cd: "native/typst_nif"}
  ]
]

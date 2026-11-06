//! Embeds the `ash_typst` version (`@version` in `mix.exs`) for
//! `Analyzer.build_info()`. The NIF and the module of one release have the
//! same version. The Typst version comes from `typst::utils::version()`.
//!
//! `AshTypst.Wasm.identity/0` gives the same two values on the server.

use std::fs;
use std::path::PathBuf;

fn main() {
    // `native/typst_nif/wasm`: `mix.exs` is three levels up.
    let manifest = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap());
    let mix_exs = manifest.join("../../../mix.exs");

    println!("cargo:rerun-if-changed={}", mix_exs.display());

    let version = fs::read_to_string(&mix_exs)
        .ok()
        .and_then(|text| {
            text.lines().find_map(|line| {
                line.trim()
                    .strip_prefix("@version \"")
                    .and_then(|rest| rest.strip_suffix('"'))
                    .map(str::to_string)
            })
        })
        .expect("the @version of mix.exs");

    println!("cargo:rustc-env=ASH_TYPST_VERSION={version}");
}

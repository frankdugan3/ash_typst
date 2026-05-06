# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](Https://conventionalcommits.org) for commit guidelines.

<!-- changelog -->

## v0.1.2 (2026-05-06)

### Added

- `root` and `font_paths` in the `typst` DSL now accept
  `{otp_app, sub_path}` tuples in addition to plain strings, mirroring
  the idiomatic `Plug.Static` pattern. Tuples are resolved at runtime
  via `Application.app_dir/2`, so paths rooted in your app's `priv/`
  resolve correctly in dev, test, and Mix releases (where `priv/`
  lives at `<release>/lib/<app>-<version>/priv/...`).

      # Before — only worked when cwd was the project root
      typst do
        root("priv/typst")
        font_paths(["priv/fonts"])
      end

      # After — works in dev, test, and releases
      typst do
        root({:my_app, "priv/typst"})
        font_paths([{:my_app, "priv/fonts"}])
      end

  Plain strings still work; behavior is unchanged for existing users.

- `AshTypst.PathResolver` — public helper for resolving the new tuple
  form, in case downstream code needs to mirror the same behavior.

## [v0.1.1-rc.1](https://github.com/frankdugan3/ash_typst/compare/v0.1.1-rc.0...v0.1.1-rc.1) (2026-02-26)




## [v0.1.0](https://github.com/frankdugan3/ash_typst/compare/v0.1.0...v0.1.0) (2026-02-26)




### Features:

* add Ash resource extension by Frank Polasek Dugan III

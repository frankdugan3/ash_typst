[![hex.pm](https://img.shields.io/hexpm/l/ash_typst.svg)](https://hex.pm/packages/ash_typst)
[![hex.pm](https://img.shields.io/hexpm/v/ash_typst.svg)](https://hex.pm/packages/ash_typst)
[![Documentation](https://img.shields.io/badge/documentation-gray)](https://hexdocs.pm/ash_typst)
[![hex.pm](https://img.shields.io/hexpm/dt/ash_typst.svg)](https://hex.pm/packages/ash_typst)
[![github.com](https://img.shields.io/github/last-commit/frankdugan3/ash_typst.svg)](https://github.com/frankdugan3/ash_typst)

# AshTypst

Precompiled Rust NIFs for rendering [Typst templates](https://typst.app) via an extensible data-encoding protocol with built-in Ash support. Compile markup to SVG, PDF, or HTML with persistent contexts that keep
fonts and compiled state in memory for fast, iterative rendering.

## Features

- **Persistent context** — font scans are cached process-wide and reused across contexts and compiles; call `AshTypst.refresh_fonts/0` to pick up newly installed fonts
- **Multi-page rendering** — compile once, render any page as SVG
- **PDF export** — proper binary output with page ranges, PDF/A standards, and document IDs
- **HTML export** — via `typst-html`
- **Virtual files** — inject data as in-memory `.typ` files your templates can `#import`
- **Sandboxed filesystem access** — opt in to reading templates and assets from a root directory; disabled by default
- **Streaming** — feed large datasets from Elixir streams into virtual files in constant memory
- **`sys.inputs`** — pass simple string parameters accessible via `#sys.inputs` in templates
- **Rich diagnostics** — compile errors include line/column numbers
- **Data encoding** — the `AshTypst.Code` protocol converts Elixir types (maps, lists, dates, decimals, Ash resources) to Typst syntax
- **Timezone-aware encoding** — dates and times are automatically shifted to a configured timezone when encoding to Typst
- **Ash Resource Extension** - define template-rendering actions inside your resources via DSL

## Documentation

- [Get Started](https://hexdocs.pm/ash_typst/get-started.html) — installation, quick start, and a tour of the API
- [Templating](https://hexdocs.pm/ash_typst/templating.html) — structuring templates and injecting data the AshTypst way
- [Multi-Language Documents](https://hexdocs.pm/ash_typst/multi-language.html) — Gettext, translated content, CLDR formatting, CJK fonts
- [Sensitive Data](https://hexdocs.pm/ash_typst/sensitive-data.html) — what reaches templates and how to keep secrets out
- [AshTypst.Resource DSL reference](https://hexdocs.pm/ash_typst/dsl-ashtypst-resource.html)

---
name: ash-typst
description: "Use this skill when rendering Typst documents (PDF, SVG, HTML, bundles) from Elixir with AshTypst — writing or editing Typst templates, declaring templates and render actions with the AshTypst.Resource DSL, using AshTypst.Context or AshTypst.ContextPool directly, or encoding Elixir data for Typst via the AshTypst.Code protocol. Always consult this skill before writing or modifying templates, render actions, or rendering pipelines."
---

## Overview

AshTypst renders [Typst](https://typst.app) documents from Elixir via
precompiled Rust NIFs. The design has one central principle: **templates are
pure Typst, and Elixir data crosses into them as encoded values** — never by
building Typst source with string interpolation.

Rendering happens through a persistent `AshTypst.Context` that keeps fonts,
virtual files, and the compiled document in memory, so repeated renders are
fast. In Ash applications, the `AshTypst.Resource` extension turns templates
into generic actions with pooled, automatically-scrubbed contexts.

## Non-negotiable rules

1. **Never interpolate values into Typst markup** (no EEx, no string
   interpolation). Typst markup is code; interpolation is code injection and
   there is no context-free escaping. Encode with `AshTypst.Code.encode/2` and
   inject via virtual files, or use `sys.inputs` for small string parameters.
2. **`@derive AshTypst.Code` is required** on any Ash resource or struct whose
   records get encoded — otherwise `Protocol.UndefinedError` is raised. Custom
   serialization: `defimpl AshTypst.Code, for: MyStruct`.
3. **Filesystem access is off by default.** Pass `:root` to opt in; everything
   under it is readable by every template in that context. Never point it at
   `"."` or a directory containing secrets. Access is sandboxed (no `..`
   escape), like the Typst CLI's `--root`.
4. **Keep templates plain `.typ` files** under the root so they compile
   standalone with the Typst CLI. Ship fixture data as an on-disk `data.typ`;
   injected virtual files shadow disk files at the same path.
5. **In Ash apps, prefer render actions** over manual contexts — they pool and
   scrub contexts, run reads with `authorize?: true`, and pass actor/tenant.

## Choosing a pipeline

| Workflow | Use |
| --- | --- |
| Documents from Ash resource data | `AshTypst.Resource` render actions → `references/resource-dsl.md` |
| Request-scoped rendering without Ash | `AshTypst.ContextPool.with_context/2` → `references/context-api.md` |
| Long-lived interactive session (live editor) | Dedicated `AshTypst.Context`, re-set only what changed |

## Minimal examples

Direct context:

```elixir
{:ok, ctx} = AshTypst.Context.new(root: "/app/priv/typst")
:ok = AshTypst.Context.set_markup(ctx, ~s(#import "data.typ": record\n= Invoice for #record.name))
:ok = AshTypst.Context.set_virtual_file(ctx, "data.typ",
  "#let record = #{AshTypst.Code.encode(record, %{})}\n")
{:ok, %AshTypst.CompileResult{}} = AshTypst.Context.compile(ctx)
{:ok, pdf} = AshTypst.Context.export_pdf(ctx)
```

Render action:

```elixir
defmodule MyApp.Invoice do
  use Ash.Resource, domain: MyApp.Domain, extensions: [AshTypst.Resource]

  @derive AshTypst.Code

  typst do
    root {:my_app, "priv/typst"}

    template :invoice do
      source "invoice.typ"
    end

    render :generate_pdf do
      template :invoice
      format :pdf
      argument :invoice_id, :string, allow_nil?: false

      read :one do
        filter expr(id == ^arg(:invoice_id))
        load [:line_items]
      end
    end
  end
end

input = Ash.ActionInput.for_action(MyApp.Invoice, :generate_pdf, %{invoice_id: id})
{:ok, %AshTypst.Document{format: :pdf, data: pdf}} = Ash.run_action(input)
```

The template imports its data: `#import "data.typ": record, args` (`records`
instead of `record` for `read :many`; only `args` when there is no `read`).

## Pitfalls agents commonly hit

- Fields the query didn't select/load are **absent** from encoded dictionaries
  — not `none`. Use `record.at("field", default: none)` when one template
  serves actions with different loads.
- `sensitive? true` keeps values out of logs/telemetry, **not** out of rendered
  documents. Use `public?: false`, de-select, or custom encoding for that.
- Virtual files and `sys.inputs` persist across compiles on a long-lived
  context — clear them before reusing the context for another tenant/actor
  (the pool and render actions do this automatically).
- `sys.inputs` values are strings only; structured data goes through encoded
  virtual files.
- `export_html/2` and `export_bundle/2` compile on their own; `render_svg/2`
  and `export_pdf/2` require a prior `compile/1`.
- For releases, use `{otp_app, subpath}` tuples for `root`/`font_paths`, not
  relative string paths.
- For large `:many` datasets, de-select unused columns — encoded output is
  Typst source the compiler parses on every compile.

## References

Read these before working in the corresponding area:

- `references/templating.md` — how to structure templates, the data boundary,
  project layout, components, assets, optional data, large documents
- `references/resource-dsl.md` — complete `AshTypst.Resource` DSL: templates,
  render actions, read blocks, pdf options, runtime behavior, introspection
- `references/context-api.md` — `AshTypst.Context`, `AshTypst.ContextPool`,
  fonts, diagnostics, and export options
- `references/data-encoding.md` — the `AshTypst.Code` protocol: type mappings,
  query-level compaction, `struct_keys`, timezones, key order
- `references/multi-language.md` — Gettext, localized calculations, CLDR
  formatting, CJK fonts, locale selection per pipeline
- `references/security.md` — what reaches templates, sensitive data, sandbox
  rules, pooling hygiene

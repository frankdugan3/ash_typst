# Sensitive Data and Sandbox Rules

Documents rendered with AshTypst often carry personal or confidential data
(invoices, statements, medical records). This reference covers what reaches
templates and how to keep secrets out.

## What the encoder lets through

The built-in Ash resource implementation (`@derive AshTypst.Code`) decides
from resource declarations:

- **Private fields are never encoded** — only `public?: true` fields.
  Keeping a field private keeps it out of documents.
- **Only what the query produced is encoded.** De-selected attributes and
  not-loaded relationships/calculations/aggregates are omitted entirely.
- **Fields forbidden by field policies are omitted silently**
  (`Ash.ForbiddenField`) — authorization-filtered reads render without
  leaking or erroring.

**`sensitive? true` does NOT affect encoding.** It redacts values from logs,
traces, and inspection — it does not make a field private, and the encoder
does not filter on it. A public attribute marked `sensitive? true` WILL be
encoded into rendered documents. Often that's intended (an invoice needs
account details that should stay out of logs); if a sensitive field must never
appear in documents:

- make it `public?: false`, or
- de-select it in the render action's query, or
- pass `struct_keys: %{MyResource => [:field, ...]}` in the encoding context
  to take exactly those keys, or
- implement `defimpl AshTypst.Code, for: MyResource` for full control.

The same applies to render action `argument :x, :string, sensitive?: true` —
it keeps the value out of *telemetry*, but the argument is still injected into
the template's `args` binding.

## Filesystem access (`:root`)

Contexts have **no filesystem access by default** — only virtual files and
Typst packages. Passing `:root` opts in, sandboxed to that directory (no `..`
escape, matching the Typst CLI's `--root`).

Everything under the root is readable by **any** template compiled in that
context, including untrusted or user-authored templates. Point the root at a
directory containing only template assets — never `"."` or a directory that
may hold secrets (`.env`, config files, credentials). The `AshTypst.Resource`
extension defaults to `"priv/typst"` for this reason.

## Context reuse hygiene

`AshTypst.ContextPool` reuses contexts across renders — including across
resources, tenants, and actors sharing a configuration. Two mechanisms prevent
leaks:

- **Check-in scrubbing**: virtual files (injected `data.typ`, streamed
  datasets) and `sys.inputs` are cleared before a context returns to the pool.
  Markup is always replaced by the next render.
- **Generational flushing**: `AshTypst.ContextPool.flush/0` (also invoked by
  `AshTypst.refresh_fonts/0`) drops every pooled context, including ones
  checked out at flush time (discarded at check-in).

If you manage long-lived contexts yourself, remember virtual files and
`sys.inputs` **persist across compiles by design**. Clear them with
`AshTypst.Context.clear_virtual_files/1` and
`AshTypst.Context.set_inputs(ctx, %{})` before reusing a context for a
different tenant or actor.

## Authorization

Render action reads run with `authorize?: true` and the calling actor/tenant,
so policies apply exactly as in any other Ash read — combined with silent
`ForbiddenField` omission, a partially-authorized read renders only what the
actor may see.

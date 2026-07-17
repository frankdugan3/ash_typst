# Sensitive Data

Documents rendered with AshTypst often contain personal or confidential
information — invoices, statements, medical records. This guide covers how
data flows into templates, what the encoding layer does and does not protect,
and how the rendering infrastructure avoids leaking data between renders.

For the broader picture of handling sensitive data in Ash, see the
[Ash security guide](https://hexdocs.pm/ash/sensitive-data.html).

## Encoding: what reaches a template

Data reaches templates through the `AshTypst.Code` protocol. The built-in
implementation for Ash resources (opted in with `@derive AshTypst.Code`)
uses your resource declarations to decide what gets encoded:

- **Private fields are never encoded.** Only fields declared `public?: true`
  are considered. Keeping a field private keeps it out of documents.
- **Only what the query produced is encoded.** Attributes de-selected in the
  query and relationships, calculations, or aggregates that were not loaded
  are omitted from the encoded data entirely — they never reach the
  template.
- **Fields forbidden by field policies are omitted silently.** A field the
  actor is not allowed to see (`Ash.ForbiddenField`) is dropped from the
  encoded data, so authorization-filtered reads render without leaking or
  erroring.

> ### `sensitive? true` does not affect encoding {: .warning}
>
> Ash's `sensitive?` flag redacts values from logs, traces, and inspection —
> it does **not** make a field private, and the built-in encoder does not
> filter on it. A public attribute marked `sensitive? true` will be encoded
> into rendered documents. This is often what you want (an invoice may need
> account details that should still stay out of logs), but if a sensitive
> field should never appear in documents, make it `public?: false`, de-select
> it in the render action's query, or use one of the escape hatches below.

When a template needs different fields than the defaults provide, make the
decision explicit and greppable:

- pass `struct_keys: %{MyResource => [:field, ...]}` in the encoding context
  to take exactly those keys for that render, or
- implement the protocol directly with `defimpl AshTypst.Code, for: MyResource`
  for full control.

## Render action arguments

Arguments in a `render` block accept Ash's `sensitive?` option:

```elixir
render :generate_statement do
  argument :account_token, :string, sensitive?: true
  # ...
end
```

This marks the value as sensitive to Ash tooling — it is redacted from logs
and error reports. Note that arguments are still injected into the template's
`args` binding regardless of this flag: `sensitive?` keeps values out of
*telemetry*, not out of the document you asked to render.

## Filesystem access (`:root`)

Contexts have **no filesystem access by default**. Templates can only read
virtual files and Typst packages unless you opt in by passing `:root` to
`AshTypst.Context.new/1`. When a root is set, access is sandboxed to that
directory — paths cannot escape it (e.g. via `..`), matching the Typst CLI's
`--root` behavior.

Everything under the root is readable by *any* template compiled in that
context, including untrusted or user-authored templates. Point the root at a
directory containing only template assets — never at `"."` or another
directory that may hold secrets (`.env`, config files, credentials). The
`AshTypst.Resource` extension defaults to `"priv/typst"` for this reason.

## Context pooling

`AshTypst.ContextPool` reuses rendering contexts across renders — including
across different resources, tenants, and actors that share a configuration.
Two mechanisms prevent data from leaking between renders:

- **Check-in scrubbing.** Before a context returns to the pool, all of its
  virtual files (the injected `data.typ`, streamed datasets, etc.) and all
  `sys.inputs` entries are cleared. Markup is always replaced by the next
  render.
- **Generational flushing.** `AshTypst.ContextPool.flush/0` (also invoked by
  `AshTypst.refresh_fonts/0`) drops every pooled context, including those
  checked out at the time of the flush — they are discarded on check-in
  rather than re-pooled.

If you bypass the pool and manage long-lived contexts yourself, remember that
virtual files and `sys.inputs` **persist across compiles by design**. Clear
them with `AshTypst.Context.clear_virtual_files/1` /
`AshTypst.Context.set_inputs(ctx, %{})` before reusing a context for a
different tenant or actor.

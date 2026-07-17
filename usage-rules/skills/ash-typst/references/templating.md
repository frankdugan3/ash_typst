# Templating the AshTypst Way

Templates are **pure Typst**; Elixir data crosses into them as **encoded
values** — never by building Typst source with string interpolation.

## Why no interpolation / EEx

- Typst already is a template language (variables, functions, loops,
  conditionals, imports, `set`/`show` styling). Layering EEx duplicates all of
  that in a second language with a second escaping discipline.
- String interpolation is code injection: a name containing `#`, `"`, `\`, or
  `]` breaks the compile at best, executes template logic at worst.
- Escaping cannot fix it because it is context-dependent — Typst is several
  syntaxes (markup, code, math, strings) with different special characters.
  The `AshTypst.Code` protocol sidesteps this: values are emitted as complete,
  well-formed Typst values that mean the same thing everywhere.
- Stable templates compile faster: Typst memoizes compilation process-wide,
  and a fixed template with changing data reuses most of the work. A template
  regenerated per render defeats the cache.
- Pure `.typ` files keep the tooling: Typst CLI, LSP, typst.app — designers
  iterate on layout without Elixir.

Mental model: the template is a **function**, the Elixir data its
**arguments**. The template's job is presentation; the query's job is
providing exactly the data the presentation needs.

## The three data channels

1. **Encoded virtual files** — the main channel for structured data:

   ```elixir
   data = "#let record = #{AshTypst.Code.encode(record, %{})}\n"
   :ok = AshTypst.Context.set_virtual_file(ctx, "data.typ", data)
   ```

   ```typ
   #import "data.typ": record
   = Invoice for #record.customer_name
   ```

   Render actions do this automatically: `record` (`:one`), `records`
   (`:many`), and/or `args` land in `data.typ`.

2. **`sys.inputs`** — small string parameters that select behavior rather than
   carry content (locale, theme, document id). Always strings:

   ```elixir
   AshTypst.Context.set_inputs(ctx, %{"locale" => "zh", "theme" => "print"})
   ```

   ```typ
   #let locale = sys.inputs.at("locale", default: "en")
   ```

3. **Files under `:root`** — the static side: shared template libraries,
   images, data files shipped with the app. Sandboxed; see `security.md`.

## Assets

- Static images live under `:root`: `#image("assets/logo.png")`.
- Dynamic images (per-tenant logos, generated charts) are injected as binary
  virtual files:

  ```elixir
  :ok = AshTypst.Context.set_virtual_file_binary(ctx, "logo.png", png_binary)
  ```

  ```typ
  #image(read("logo.png", encoding: none))
  ```

- Typst Universe packages import as usual (`#import "@preview/cetz:0.3.1"`);
  downloaded once per machine and cached on disk.

## Project layout

```text
priv/typst/
├── invoice.typ          # entry template, one per document kind
├── statement.typ
├── lib/
│   ├── theme.typ        # colors, set/show rules, page setup
│   ├── components.typ   # reusable pieces: address blocks, totals tables
│   └── i18n.typ         # translations
├── assets/
│   └── logo.png
└── data.typ             # fixture data for standalone development
```

Entry templates stay thin — import the pieces, import the data, apply them:

```typ
// invoice.typ
#import "lib/theme.typ": theme
#import "lib/components.typ": address-block, totals
#import "data.typ": record, args

#show: theme

= Invoice #args.invoice_number
#address-block(record.customer)
#totals(record.line_items)
```

Two load-bearing properties:

- **Virtual files shadow disk files.** The on-disk `data.typ` holds fixture
  data so the template compiles standalone; at render time the app injects the
  real `data.typ` as a virtual file, which takes precedence. Same template, no
  modification, real data.
- **The Typst CLI sees the same world:**

  ```sh
  typst watch invoice.typ --root priv/typst --input locale=zh
  ```

## Components and styling

Use Typst functions for anything that repeats; keep styling in `set`/`show`
rules rather than sprinkled through content:

```typ
// lib/components.typ
#let address-block(party) = block[
  *#party.name* \
  #party.street \
  #party.city, #party.postal_code
]

#let totals(items) = {
  let total = items.map(i => i.amount).sum()
  table(
    columns: (1fr, auto, auto),
    ..items.map(i => (i.description, str(i.quantity), [#i.amount])).flatten(),
    [*Total*], [], [*#total*],
  )
}

// lib/theme.typ
#let theme(doc) = {
  set page(margin: 2cm)
  set text(10pt, font: ("Libertinus Serif",))
  show heading.where(level: 1): set text(16pt, weight: "bold")
  doc
}
```

## Optional and varying data

Encoding is compacted to the query: fields the query didn't select or load are
**absent** from the encoded dictionary, not `none`. Ideally each render
action's query provides exactly what its template references. When one
template serves actions with different loads:

```typ
#let notes = record.at("notes", default: none)
#if notes != none [ == Notes \ #notes ]
```

Values that *were* queried but are empty come through as `none`, so
`record.at(...)` with a `none` default handles both cases with one idiom.

## Large documents

1. **Stream the data.** `AshTypst.Context.stream_virtual_file/4` encodes an
   enumerable in batches — Elixir memory stays flat. Render actions with
   `:many` cardinality stream automatically (`batch_size` on the `read`
   block).
2. **De-select what the template doesn't use.** Encoded output is Typst source
   parsed on every compile — unused columns are overhead multiplied by row
   count. Use `select` in the `read` block or `Ash.Query.select/2`.
3. **Aggregate in the query when possible.** Sums/counts the data layer can
   compute (Ash aggregates) are cheaper there than in template code iterating
   a huge array.

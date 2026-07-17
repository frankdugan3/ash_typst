# Templating

This guide covers how to structure and write Typst templates the AshTypst
way: templates are **pure Typst**, and Elixir data crosses into them as
**encoded values** — never by building Typst source with string
interpolation.

## Philosophy: data in, documents out

A common first instinct is to reach for EEx and interpolate values into
Typst markup the way you would build HTML. AshTypst deliberately does not
work that way, for a few reasons:

- **Typst already is a template language.** It has variables, functions,
  loops, conditionals, imports, and a styling system (`set`/`show` rules).
  Layering EEx on top duplicates all of that, poorly, in a second language
  with a second escaping discipline.
- **String interpolation is code injection.** Typst markup is _code_. A
  customer named `#panic()` — or more realistically, a name containing `#`,
  `"`, `\`, or `]` — interpolated raw into markup will at best break the
  compile and at worst execute template logic you didn't write.
- **Escaping cannot fix that, because it is context-dependent.** Typst is
  several syntaxes in one: markup mode, code mode, math mode, and string
  literals each have different special characters and different escape
  rules. Which characters are dangerous depends on where in the template
  the value lands — `"` is harmless in markup but terminates a string in
  code mode; `$` is harmless in a string but switches markup into math
  mode. Escaping correctly would mean parsing the surrounding Typst at
  every insertion point, which is impractical. The `AshTypst.Code`
  protocol sidesteps the problem instead of solving it: values are never
  spliced into an unknown syntactic context — they are emitted as
  complete, well-formed Typst _values_ (a properly quoted `str`, a
  `datetime(...)`, a dictionary) that mean the same thing everywhere an
  expression is valid.
- **Stable templates compile faster.** Typst memoizes compilation
  process-wide. When the template is a fixed artifact and only the data
  changes, repeated renders reuse most of the compilation work. A template
  regenerated per render by EEx defeats that cache.
- **Pure Typst files keep the tooling.** Templates that are plain `.typ`
  files work with the Typst CLI, the LSP, and typst.app — your designers
  don't need Elixir running to iterate on layout (more on this below).

The mental model: treat a template like a **function** and your Elixir data
like its **arguments**. The template's job is presentation; the query's job
is providing exactly the data the presentation needs.

## The data boundary

There are three channels for getting information into a template:

1. **Encoded virtual files** — the main channel for structured data. Encode
   any supported Elixir value (or stream a large dataset) into an in-memory
   `.typ` file the template imports:

   ```elixir
   data = "#let record = #{AshTypst.Code.encode(record, %{})}\n"
   :ok = AshTypst.Context.set_virtual_file(ctx, "data.typ", data)
   ```

   ```typ
   #import "data.typ": record
   = Invoice for #record.customer_name
   ```

   The Ash resource extension does this for you: render actions inject
   `record` (single result), `records` (list), and/or `args` (action
   arguments) into `data.typ`.

2. **`sys.inputs`** — for small string parameters that select behavior
   rather than carry content: a locale, a theme name, a document id.
   Values are always strings:

   ```elixir
   AshTypst.Context.set_inputs(ctx, %{"locale" => "zh", "theme" => "print"})
   ```

   ```typ
   #let locale = sys.inputs.at("locale", default: "en")
   ```

3. **Files under `:root`** — for the static side of templating: shared
   template libraries, images, data files that ship with your app. See the
   [Get Started guide](get-started.md#filesystem-access) for the sandbox
   rules.

## Assets

- **Static images** live under `:root` and are referenced relatively:
  `#image("assets/logo.png")`.
- **Dynamic images** (per-tenant logos, generated charts) are injected as
  binary virtual files and read explicitly:

  ```elixir
  :ok = AshTypst.Context.set_virtual_file_binary(ctx, "logo.png", png_binary)
  ```

  ```typ
  #image(read("logo.png", encoding: none))
  ```

- **Packages** from [Typst Universe](https://typst.app/universe) import as
  usual (`#import "@preview/cetz:0.3.1"`); they are downloaded once per
  machine and cached on disk.

## Rendering pipelines

How you hold the context depends on the workflow:

- **Render actions** (the common case): declare templates on the resource
  and let the extension manage contexts — they are pooled and scrubbed
  between renders automatically.
- **Request-scoped rendering** without Ash: wrap each render in
  `AshTypst.ContextPool.with_context/2`.
- **Long-lived sessions** (an editor holding state across keystrokes): keep
  a dedicated context and re-set only what changed between compiles.

See the [Get Started guide](get-started.md) for examples of each.

## Project layout

A workable layout for anything beyond a single template:

```text
priv/typst/
├── invoice.typ          # entry template, one per document kind
├── statement.typ
├── lib/
│   ├── theme.typ        # colors, set/show rules, page setup
│   ├── components.typ   # reusable pieces: address blocks, totals tables
│   └── i18n.typ         # translations (see below)
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

Two properties of this layout do a lot of work:

- **Virtual files shadow disk files.** The `data.typ` on disk holds fixture
  data, so the template compiles standalone. At render time your app injects
  the real `data.typ` as a virtual file, which takes precedence. Same
  template, no modification, real data.
- **The Typst CLI sees the same world.** Because everything under
  `priv/typst` is plain Typst, layout work needs no Elixir at all:

  ```sh
  typst watch invoice.typ --root priv/typst --input locale=zh
  ```

## Writing template components

Use Typst functions for anything that repeats, and keep styling in
`set`/`show` rules rather than sprinkled through content:

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
```

```typ
// lib/theme.typ
#let theme(doc) = {
  set page(margin: 2cm)
  set text(10pt, font: ("Libertinus Serif",))
  show heading.where(level: 1): set text(16pt, weight: "bold")
  doc
}
```

## Optional and varying data

The built-in encoding is compacted to the query (see `AshTypst.Code`):
fields the query didn't select or load are _absent_ from the encoded
dictionary, not `none`. Ideally each render action's query provides exactly
what its template references, and this never comes up. When one template
serves actions with different loads, read the varying fields with a
default:

```typ
#let notes = record.at("notes", default: none)
#if notes != none [ == Notes \ #notes ]
```

Values that _were_ queried but are empty (a `belongs_to` that resolved to
nothing, a nullable attribute) come through as `none` — so `record.at(...)`
with a `none` default handles both cases with one idiom.

## Large documents

For documents rendering thousands of records, three levers matter:

1. **Stream the data.** `AshTypst.Context.stream_virtual_file/4` encodes an
   enumerable into the virtual file in batches, so Elixir memory stays flat
   regardless of dataset size. Render actions with `:many` cardinality
   stream automatically (`batch_size` is configurable on the `read` block).
2. **De-select what the template doesn't use.** Encoded output is Typst
   source the compiler parses and evaluates on every compile — unused
   columns are pure overhead, multiplied by row count. Use `select` in the
   render action's `read` block (or `Ash.Query.select/2`) to keep the
   payload minimal.
3. **Let the template do the aggregation it can't avoid, and the query do
   the rest.** Sums and counts your data layer can compute (Ash aggregates)
   are cheaper there than in template code iterating a huge array.

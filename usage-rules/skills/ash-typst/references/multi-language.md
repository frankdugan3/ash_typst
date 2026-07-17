# Multi-Language Documents

Keep Elixir as the source of truth for localization — Gettext for prose,
ex_cldr/localize for dates, numbers, currency — and inject **resolved**
translations as data, the same way records are injected. Don't rebuild a
localization stack inside templates.

## Translating with Gettext

Resolve strings for the requested locale at render time and encode them as a
dictionary the template imports:

```elixir
defp translations(locale) do
  Gettext.with_locale(MyApp.Gettext, locale, fn ->
    %{invoice: gettext("Invoice"), date: gettext("Date"), total: gettext("Total")}
  end)
end

data = """
#let locale = #{AshTypst.Code.encode(locale, %{})}
#let t = #{AshTypst.Code.encode(translations(locale), %{})}
"""
:ok = AshTypst.Context.set_virtual_file(ctx, "i18n.typ", data)
```

```typ
#import "i18n.typ": locale, t

// `lang` improves hyphenation, smart quotes, accessibility metadata.
// The font list falls back to a CJK font for characters the primary font lacks.
#set text(lang: locale, font: ("Libertinus Serif", "Noto Serif CJK SC"))

= #t.invoice
```

All of Gettext keeps working (`.po` files, plurals, interpolation) because
translation happens in Elixir.

## Localizing record data with calculations

Strings derived from record data — status labels, formatted amounts, humanized
dates — belong on the resource as **public calculations**, which can use
Gettext or CLDR directly:

```elixir
defmodule MyApp.Invoice.StatusLabel do
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:status]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn record ->
      Gettext.gettext(MyApp.Gettext, "invoice.status.#{record.status}")
    end)
  end
end
```

```elixir
calculations do
  calculate :status_label, :string, MyApp.Invoice.StatusLabel, public?: true
end
```

Gettext's locale is process-scoped — set it before running the action (a
Phoenix plug typically already does) and every calculation resolves in the
caller's locale. Load them in the render action's `read` block
(`load [:status_label]`); they encode like any other field and are subject to
query-level compaction.

Formatting follows the same pattern with ex_cldr
(`Cldr.Number.to_string!(total, MyApp.Cldr, currency: currency)`) or localize
(`Localize.Date.to_string(date, format: :long)`) — both resolve against a
process-scoped locale. The template then treats `record.formatted_total` like
any other string; no locale logic in Typst.

Dates encode as real Typst `datetime` values (timezone-shifted when the
encoding context sets `timezone`) — keep them that way when the template needs
an actual date; use a calculation when you want a humanized localized string.

## Translated content with AshTranslation

When content itself is stored in multiple languages (product names,
descriptions), [ash_translation](https://hexdocs.pm/ash_translation) stores
per-locale values in an embedded `translations` attribute and swaps them in:

```elixir
use Ash.Resource, extensions: [AshTranslation.Resource]

translations do
  public? true
  fields [:name, :description]
  locales [:it, :zh]
end
```

```elixir
translated = AshTranslation.translate(record, :zh)
# translated.name now holds the zh value — encode like any other record
```

## Template-owned translations

The alternative keeps a translations dictionary in the template layer:

```typ
// lib/i18n.typ
#let translations = (
  en: (invoice: "Invoice", total: "Total"),
  zh: (invoice: "发票", total: "总计"),
)
#let t(locale, key) = translations.at(locale).at(key)
```

This trades away the Gettext toolchain — reserve it for designer-owned
templates or templates that must compile standalone with the CLI
(`typst watch invoice.typ --root priv/typst --input locale=zh`, read via
`sys.inputs.at("locale", default: "en")`).

## Locale selection per pipeline

- **Render actions** — localized *data* comes from calculations resolved in
  the caller's process locale. For the template's own chrome (headings, column
  labels), pass the locale as an action argument — it reaches the template as
  `args.locale` — and use a template-owned dictionary keyed by it. (Render
  actions inject only `record`/`records`/`args`; template `inputs` are static
  DSL configuration.)
- **Direct context / pool usage** — same calculation-loaded data, plus full
  control of the boundary: inject a resolved translations file (Gettext
  approach) or `set_inputs(ctx, %{"locale" => locale})` (template-owned
  approach).

## Fonts for CJK output

Ship fonts with the app rather than depending on the host system:

```elixir
typst do
  root {:my_app, "priv/typst"}
  font_paths [{:my_app, "priv/fonts"}]
end
```

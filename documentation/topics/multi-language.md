# Multi-Language Documents

Your application almost certainly already has a localization stack —
[Gettext](https://hexdocs.pm/gettext) for prose, and
[ex_cldr](https://hexdocs.pm/ex_cldr) (or the newer `localize` suite of
packages built on top of it) for dates, numbers, and currency. Don't
rebuild that stack inside your templates: keep Elixir as the source of
truth and inject *resolved* translations as data, the same way you inject
records (see the [Templating guide](templating.md) for the general data
boundary).

## Translating with Gettext

Resolve the strings for the requested locale at render time and encode
them as a dictionary the template imports:

```elixir
import MyApp.Gettext

defp translations(locale) do
  Gettext.with_locale(MyApp.Gettext, locale, fn ->
    %{
      invoice: gettext("Invoice"),
      date: gettext("Date"),
      total: gettext("Total")
    }
  end)
end

def render_invoice(ctx, locale) do
  data = """
  #let locale = #{AshTypst.Code.encode(locale, %{})}
  #let t = #{AshTypst.Code.encode(translations(locale), %{})}
  """

  :ok = AshTypst.Context.set_virtual_file(ctx, "i18n.typ", data)
  # ... inject records, compile, export
end
```

```typ
#import "i18n.typ": locale, t

// `lang` improves hyphenation, smart quotes, and accessibility metadata.
// The font list falls back to a CJK font for characters the primary
// font lacks.
#set text(
  lang: locale,
  font: ("Libertinus Serif", "Noto Serif CJK SC"),
)

= #t.invoice
```

Everything Gettext gives you keeps working — `.po` files, translator
workflows, plurals, interpolation — because translation happens in Elixir
where the domain data lives.

## Localizing data with calculations

For Ash resources, strings derived from record data — status labels,
pluralized counts, formatted amounts — belong on the resource itself as
public calculations. A module calculation can use Gettext (or CLDR)
directly:

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

Gettext's locale is process-scoped, so set it before running the action
(as a Phoenix plug typically already does) and every calculation resolves
in the caller's locale — no locale threading required. Calculations can
also take an explicit `argument` when ambient locale isn't appropriate.

This composes with everything else in these guides: the localized strings
are loaded by the query (`load [:status_label]` in the render action's
`read` block), encoded onto the record like any other field, and subject
to the same query-level compaction — templates that don't need them
simply don't load them.

## Translated content with AshTranslation

When the *content itself* is stored in multiple languages — product names,
descriptions, any authored text — writing a calculation per field gets
tedious. [ash_translation](https://hexdocs.pm/ash_translation) is a
simpler option: it stores per-locale values in an embedded `translations`
attribute on the resource and swaps them in on demand:

```elixir
use Ash.Resource,
  extensions: [AshTranslation.Resource]

translations do
  public? true
  fields [:name, :description]
  locales [:it, :zh]
end
```

```elixir
record = Ash.get!(MyApp.Product, product_id)
translated = AshTranslation.translate(record, :zh)
# `translated.name` and `translated.description` now hold the zh values —
# encode it like any other record. Single fields:
# AshTranslation.translate_field(record, :name, :zh)
```

## Formatting dates, numbers, and currency

Locale-sensitive *formatting* follows the same rule: format in Elixir with
[ex_cldr](https://hexdocs.pm/ex_cldr) or
[localize](https://hexdocs.pm/localize), exposed as calculations. Both
resolve against a process-scoped locale (`Cldr.put_locale/1` /
`Localize.put_locale/1`), so the same plug that sets your Gettext locale
covers formatting too.

Currency with ex_cldr (using your `MyApp.Cldr` backend):

```elixir
defmodule MyApp.Invoice.FormattedTotal do
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:total, :currency]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn record ->
      # Uses the process locale: "$1,234.56" for en, "¥1,234.56" for zh/CNY
      Cldr.Number.to_string!(record.total, MyApp.Cldr, currency: record.currency)
    end)
  end
end
```

A humanized date with localize (no backend module needed):

```elixir
defmodule MyApp.Invoice.IssuedOn do
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:issued_at]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn record ->
      # "March 22, 2025" for en, "2025年3月22日" for zh
      {:ok, formatted} = Localize.Date.to_string(record.issued_at, format: :long)
      formatted
    end)
  end
end
```

```elixir
calculations do
  calculate :formatted_total, :string, MyApp.Invoice.FormattedTotal, public?: true
  calculate :issued_on, :string, MyApp.Invoice.IssuedOn, public?: true
end
```

The template then treats `record.formatted_total` and `record.issued_on`
like any other string — no locale logic in Typst at all.

Dates encode as real Typst `datetime` values (timezone-shifted when the
encoding context sets `timezone`) — keep them that way when the template
needs an actual date to work with. When you want a humanized, localized
string instead, use a calculation as above.

## Template-owned translations

The alternative is keeping a translations dictionary in the template
layer:

```typ
// lib/i18n.typ
#let translations = (
  en: (invoice: "Invoice", total: "Total"),
  zh: (invoice: "发票", total: "总计"),
)

#let t(locale, key) = translations.at(locale).at(key)
```

This trades away the Gettext toolchain, so reserve it for cases where it
earns its keep: designer-owned templates where translations are part of
the template artifact, or templates that must compile standalone with the
CLI (`typst watch invoice.typ --root priv/typst --input locale=zh`, read
via `sys.inputs.at("locale", default: "en")`).

## Locale selection per pipeline

- **Render actions** — localized *data* comes from calculations loaded in
  the `read` block, resolved in the caller's process locale. For the
  template's own chrome (headings, column labels), pass the locale as an
  action argument — it reaches the template as `args.locale` — and use a
  template-owned dictionary keyed by it. (Render actions inject only
  `record`/`records`/`args` into `data.typ`; template `inputs` are static
  DSL configuration.)
- **Direct `AshTypst.Context` / pool usage** — same calculation-loaded
  data, plus full control of the boundary: inject a resolved translations
  file for chrome (Gettext approach) or set the locale with
  `set_inputs(ctx, %{"locale" => locale})` (template-owned approach).

## Fonts for CJK output

Ship the fonts with your app rather than depending on the host system,
and point the context at them:

```elixir
typst do
  root {:my_app, "priv/typst"}
  font_paths [{:my_app, "priv/fonts"}]
end
```

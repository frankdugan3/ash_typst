defmodule AshTypst.TemplateSourceTest do
  @moduledoc """
  Compile-time Typst syntax validation of file-based templates (`source`).

  Fixtures live in `test/fixtures/typst`. Inline `~TYPST` markup is covered by
  `AshTypst.SigilTest`.
  """
  # Not async: these tests assert on the exact compiler output captured from
  # stderr, which is global, so output from concurrently compiling tests in
  # other modules would leak in. Synchronous modules run after async ones.
  use ExUnit.Case, async: false

  import AshTypst.Test.DslError, only: [normalize: 1, __capture_dsl_error__: 1]

  defmodule TestDomain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      allow_unregistered? true
    end
  end

  setup do
    # Source annotations are only captured when `debug_info` is enabled, which
    # is off by default in `.exs` files. Enabling it lets the DSL errors point
    # at the `source` option. See Spark's "Using Source Annotations".
    debug_info? = Code.get_compiler_option(:debug_info)
    Code.put_compiler_option(:debug_info, true)
    on_exit(fn -> Code.put_compiler_option(:debug_info, debug_info?) end)
    :ok
  end

  # The line in this file containing `code`, so assertions on the location of
  # the `source` option survive edits that shift line numbers.
  defp line_of(code) do
    __ENV__.file
    |> File.read!()
    |> String.split("\n")
    |> Enum.find_index(&(String.trim(&1) == code))
    |> Kernel.+(1)
  end

  defp source_line(%Spark.Error.DslError{location: location}), do: :erl_anno.line(location)

  # A compiler warning emitted for the `source` option written as `code`:
  # the warning's own indentation is removed, and the line number of `code`
  # in this file (in Elixir's snippet and `└─` pointer) becomes `<LINE>`. A
  # warning pointing at any other line therefore fails to match.
  defp normalize_warning(stderr, code) do
    line = line_of(code)

    [first | _] =
      lines = stderr |> String.trim_trailing() |> String.trim_leading("\n") |> String.split("\n")

    indent = byte_size(first) - byte_size(String.trim_leading(first))

    lines
    |> Enum.map_join("\n", &String.replace(&1, ~r/^ {0,#{indent}}/, ""))
    |> String.replace("#{line} │", "<LINE> │")
    |> String.replace(":#{line}: (file)", ":<LINE>: (file)")
  end

  test "accepts a template whose imports and inputs only exist at render time" do
    stderr =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        defmodule ValidSource do
          use Ash.Resource, domain: TestDomain, extensions: [AshTypst.Resource]

          typst do
            root "test/fixtures/typst"

            template :doc do
              source "valid.typ"
            end
          end
        end
      end)

    assert stderr == ""
  end

  test "reports a syntax error with the template file's path, line and column" do
    {error, stderr} =
      __capture_dsl_error__(fn ->
        defmodule UnclosedSource do
          use Ash.Resource, domain: TestDomain, extensions: [AshTypst.Resource]

          typst do
            root "test/fixtures/typst"

            template :doc do
              source "unclosed.typ"
            end
          end
        end
      end)

    assert normalize(Exception.message(error)) == """
           [AshTypst.TemplateSourceTest.UnclosedSource]
           typst -> doc -> source defined in <FILE:LINE>:
             Template :doc: `source` file has invalid Typst syntax.

             test/fixtures/typst/unclosed.typ:4:14: unclosed delimiter
                │
              4 │ #let total = (1, 2
                │              ~
                │\
           """

    assert error.path == [:typst, :doc, :source]
    assert source_line(error) == line_of(~s(source "unclosed.typ"))

    # Spark also emits the error as a warning at the `source` option, so the
    # compiler output (and editors) point at both the template file location
    # and the DSL line that references it.
    assert normalize_warning(stderr, ~s(source "unclosed.typ")) == """
           warning: Template :doc: `source` file has invalid Typst syntax.

             test/fixtures/typst/unclosed.typ:4:14: unclosed delimiter
                │
              4 │ #let total = (1, 2
                │              ~
                │
           │
           <LINE> │               source "unclosed.typ"
           │               ~~~~~~~~~~~~~~~~~~~~~
           │
           └─ test/ash_typst_template_source_test.exs:<LINE>: (file)\
           """
  end

  test "reports every syntax error in the file, with hints" do
    {error, _stderr} =
      __capture_dsl_error__(fn ->
        defmodule MultipleErrorsSource do
          use Ash.Resource, domain: TestDomain, extensions: [AshTypst.Resource]

          typst do
            root "test/fixtures/typst"

            template :report do
              source "multiple_errors.typ"
            end
          end
        end
      end)

    assert normalize(Exception.message(error)) == """
           [AshTypst.TemplateSourceTest.MultipleErrorsSource]
           typst -> report -> source defined in <FILE:LINE>:
             Template :report: `source` file has invalid Typst syntax.

             test/fixtures/typst/multiple_errors.typ:2:12: expected expression
                │
              2 │ #f(a: 1, b:)
                │            ^
                │

             test/fixtures/typst/multiple_errors.typ:3:4: the character `#` is not valid in code
                │
              3 │ #f(#x)
                │    ~
                │
               hint: you are already in code mode
               hint: try removing the `#`\
           """

    assert source_line(error) == line_of(~s(source "multiple_errors.typ"))
  end

  test "places markers by codepoint column in nested, indented template files" do
    {error, _stderr} =
      __capture_dsl_error__(fn ->
        defmodule NestedSource do
          use Ash.Resource, domain: TestDomain, extensions: [AshTypst.Resource]

          typst do
            root "test/fixtures/typst"

            template :doc do
              source "nested/indented.typ"
            end
          end
        end
      end)

    assert normalize(Exception.message(error)) == """
           [AshTypst.TemplateSourceTest.NestedSource]
           typst -> doc -> source defined in <FILE:LINE>:
             Template :doc: `source` file has invalid Typst syntax.

             test/fixtures/typst/nested/indented.typ:4:20: expected expression
                │
              4 │   Nested: #f(größe:)
                │                    ^
                │\
           """
  end

  test "resolves an {otp_app, sub_path} root relative to the project being compiled" do
    {error, _stderr} =
      __capture_dsl_error__(fn ->
        defmodule AppRootSource do
          use Ash.Resource, domain: TestDomain, extensions: [AshTypst.Resource]

          typst do
            root {:ash_typst, "test/fixtures/typst"}

            template :doc do
              source "unclosed.typ"
            end
          end
        end
      end)

    assert normalize(Exception.message(error)) =~
             "test/fixtures/typst/unclosed.typ:4:14: unclosed delimiter"
  end

  test "emits syntax warnings at the `source` option, with the file location" do
    stderr =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        defmodule WarningSource do
          use Ash.Resource, domain: TestDomain, extensions: [AshTypst.Resource]

          typst do
            root "test/fixtures/typst"

            template :notes do
              source "warning.typ"
            end
          end
        end
      end)

    assert normalize_warning(stderr, ~s(source "warning.typ")) == """
           warning: Template :notes: `source` file has a Typst syntax warning.

           test/fixtures/typst/warning.typ:1:9: no text within stars
              │
            1 │ = Notes **
              │         ~~
              │
             hint: using multiple consecutive stars (e.g. **) has no additional effect
           │
           <LINE> │               source "warning.typ"
           │               ~~~~~~~~~~~~~~~~~~~~
           │
           └─ test/ash_typst_template_source_test.exs:<LINE>: (file)\
           """
  end

  test "warns when the template file cannot be found at compile time" do
    stderr =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        defmodule MissingSource do
          use Ash.Resource, domain: TestDomain, extensions: [AshTypst.Resource]

          typst do
            root "test/fixtures/typst"

            template :doc do
              source "missing.typ"
            end
          end
        end
      end)

    assert normalize_warning(stderr, ~s(source "missing.typ")) == """
           warning: Template :doc: `source` file "missing.typ" was not found in root "test/fixtures/typst" at compile time, so its Typst syntax was not checked.
           │
           <LINE> │               source "missing.typ"
           │               ~~~~~~~~~~~~~~~~~~~~
           │
           └─ test/ash_typst_template_source_test.exs:<LINE>: (file)\
           """
  end

  test "registers template files as external resources so edits recompile the resource" do
    defmodule ExternalResourceSource do
      use Ash.Resource, domain: TestDomain, extensions: [AshTypst.Resource]

      @after_compile __MODULE__

      typst do
        root "test/fixtures/typst"

        template :doc do
          source "valid.typ"
        end
      end

      def __after_compile__(env, _bytecode) do
        send(self(), {:external_resources, Module.get_attribute(env.module, :external_resource)})
      end
    end

    assert_received {:external_resources, resources}
    assert "test/fixtures/typst/valid.typ" in resources
  end
end

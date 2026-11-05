defmodule AshTypst.SigilTest do
  use ExUnit.Case, async: true

  doctest AshTypst.Sigil
  doctest AshTypst, only: [validate_syntax: 1]

  import AshTypst.Sigil

  alias AshTypst.Sigil.SyntaxError

  @file_name "lib/example.ex"

  defp compile!(source), do: Code.compile_string(source, @file_name)

  defp compile_error(source) do
    assert_raise SyntaxError, fn -> compile!(source) end
  end

  defp location(%SyntaxError{} = e), do: {e.line, e.column, e.end_line, e.end_column}

  describe "~TYPST sigil" do
    test "returns plain string" do
      assert ~TYPST"= Hello" == "= Hello"
    end

    test "preserves # characters literally" do
      assert ~TYPST"#let x = 1" == "#let x = 1"
    end

    test "works with heredoc" do
      markup = ~TYPST"""
      = Title
      #import "data.typ": record
      *#record.name*
      """

      assert markup == "= Title\n#import \"data.typ\": record\n*#record.name*\n"
    end

    test "preserves Typst expressions without Elixir interpolation" do
      markup = ~TYPST"#{1 + 2} is Typst code"
      assert markup == "\#{1 + 2} is Typst code"
    end

    test "works with pipe delimiters" do
      assert ~TYPST|#set page(width: 3in)| == "#set page(width: 3in)"
    end
  end

  describe "compile-time validation" do
    test "accepts markup whose imports and inputs only exist at render time" do
      assert {[], []} =
               Code.with_diagnostics(fn ->
                 compile!(~S'''
                 import AshTypst.Sigil

                 ~TYPST"""
                 #import "data.typ": record
                 #import "@preview/cetz:0.3.4": canvas
                 #let name = sys.inputs.at("name", default: undefined_variable)
                 = #record.title
                 #canvas({ draw-things(name) })
                 """
                 ''')
               end)
    end

    test "reports an error in an inline sigil at its position in the Elixir file" do
      error =
        compile_error(~S'''
        import AshTypst.Sigil
        x = ~TYPST"#let x = (1, 2"
        ''')

      assert Exception.message(error) == """
             lib/example.ex:2:21: unclosed delimiter
                │
              2 │ #let x = (1, 2
                │          ~
                │\
             """

      assert location(error) == {2, 21, 2, 22}
      assert error.file == @file_name
    end

    test "accounts for the delimiter of an inline sigil" do
      error =
        compile_error(~S'''
        import AshTypst.Sigil
            ~TYPST|= Title #f(a: 1, b:)|
        ''')

      assert location(error) == {2, 31, 2, 32}
    end

    test "reports an error in a heredoc sigil, accounting for its indentation" do
      error =
        compile_error(~S'''
        defmodule AshTypst.SigilTest.HeredocError do
          import AshTypst.Sigil

          def markup do
            ~TYPST"""
            = Title
            #let x = (1, 2
            """
          end
        end
        ''')

      assert Exception.message(error) == """
             lib/example.ex:7:14: unclosed delimiter
                │
              7 │ #let x = (1, 2
                │          ~
                │\
             """

      assert location(error) == {7, 14, 7, 15}
    end

    test "reports every error with hints, locating the raise at the first" do
      error =
        compile_error(~S'''
        import AshTypst.Sigil

        ~TYPST"""
        = Title
        #f(a: 1, b:)
        #f(#x)
        """
        ''')

      assert Exception.message(error) == """
             lib/example.ex:5:12: expected expression
                │
              5 │ #f(a: 1, b:)
                │            ^
                │

             lib/example.ex:6:4: the character `#` is not valid in code
                │
              6 │ #f(#x)
                │    ~
                │
               hint: you are already in code mode
               hint: try removing the `#`\
             """

      # Empty ranges are widened to one column so editors can underline them.
      assert location(error) == {5, 12, 5, 13}

      assert [%{message: "expected expression"}, %{message: "the character" <> _}] =
               error.diagnostics
    end

    test "uses two-digit gutters for line numbers of two digits" do
      error =
        compile_error(~S'''
        import AshTypst.Sigil








        ~TYPST"#let x = (1, 2"
        ''')

      assert Exception.message(error) == """
             lib/example.ex:10:17: unclosed delimiter
                 │
              10 │ #let x = (1, 2
                 │          ~
                 │\
             """
    end

    test "counts columns in codepoints, not bytes" do
      error =
        compile_error(~S'''
        import AshTypst.Sigil
        ~TYPST"= Größe #f(a:)"
        ''')

      assert location(error) == {2, 21, 2, 22}
    end

    test "emits syntax warnings as compiler warnings at their position" do
      assert {[], [warning]} =
               Code.with_diagnostics(fn ->
                 compile!(~S'''
                 import AshTypst.Sigil
                 ~TYPST"= Hi **"
                 ''')
               end)

      assert %{
               severity: :warning,
               position: {2, 13},
               file: @file_name,
               message:
                 "no text within stars\n" <>
                   "  hint: using multiple consecutive stars (e.g. **) has no additional effect"
             } = warning
    end

    @tag :tmp_dir
    test "produces a compiler diagnostic with a source span for editors", %{tmp_dir: dir} do
      file = Path.join(dir, "sigil_lsp.ex")

      File.write!(file, ~S'''
      defmodule AshTypst.SigilTest.LspDiagnostic do
        import AshTypst.Sigil

        def markup do
          ~TYPST"""
          = Report
          #let total = (1, 2
          """
        end
      end
      ''')

      {result, _stderr} =
        ExUnit.CaptureIO.with_io(:stderr, fn ->
          Kernel.ParallelCompiler.compile([file], return_diagnostics: true)
        end)

      assert {:error, [diagnostic], _warnings} = result

      assert %{
               severity: :error,
               file: ^file,
               position: {7, 18},
               span: {7, 19},
               details: {:error, %SyntaxError{}}
             } = diagnostic
    end

    test "validates markup inside resource template blocks" do
      error =
        compile_error(~S'''
        defmodule AshTypst.SigilTest.BadTemplateMarkup do
          use Ash.Resource,
            domain: nil,
            validate_domain_inclusion?: false,
            extensions: [AshTypst.Resource]

          typst do
            template :doc do
              markup ~TYPST"""
              = Invoice
              #let total = (1, 2
              """
            end
          end
        end
        ''')

      assert Exception.message(error) == """
             lib/example.ex:11:20: unclosed delimiter
                 │
              11 │ #let total = (1, 2
                 │              ~
                 │\
             """
    end
  end

  # The text of `source` covered by an Elixir `{line, column, end_line,
  # end_column}` range (end exclusive). Asserting on it checks that a reported
  # location really points at the offending markup in the Elixir file.
  defp text_at(source, {line, column, end_line, end_column}) do
    lines = String.split(source, "\n")

    if line == end_line do
      lines |> Enum.at(line - 1) |> String.slice((column - 1)..(end_column - 2)//1)
    else
      first = lines |> Enum.at(line - 1) |> String.slice((column - 1)..-1//1)
      middle = Enum.slice(lines, line..(end_line - 2)//1)
      last = lines |> Enum.at(end_line - 1) |> String.slice(0..(end_column - 2)//1)
      Enum.join([first | middle] ++ [last], "\n")
    end
  end

  describe "marker placement" do
    test "inline sigil nested deep in code" do
      source = ~S'''
      defmodule AshTypst.SigilTest.DeepInline do
        import AshTypst.Sigil

        def markup(kind) do
          case kind do
            :invoice ->
              Enum.map([1], fn _ ->
                ~TYPST"= Invoice #f(total: (1, 2)"
              end)
          end
        end
      end
      '''

      error = assert_raise SyntaxError, fn -> compile!(source) end

      assert Exception.message(error) == """
             lib/example.ex:8:30: unclosed delimiter
                │
              8 │ = Invoice #f(total: (1, 2)
                │             ~
                │\
             """

      assert location(error) == {8, 30, 8, 31}
      assert text_at(source, location(error)) == "("
    end

    test "inline sigil preceded by other code on the same line" do
      source = ~S'''
      import AshTypst.Sigil
          IO.puts(String.upcase(~TYPST|#let = 1|))
      '''

      error = assert_raise SyntaxError, fn -> compile!(source) end

      assert Exception.message(error) == """
             lib/example.ex:2:38: expected pattern
                │
              2 │ #let = 1
                │     ^
                │\
             """

      # The empty range after `#let` is widened to the following column.
      assert location(error) == {2, 38, 2, 39}

      assert source
             |> String.split("\n")
             |> Enum.at(1)
             |> String.slice(0, 37)
             |> String.ends_with?("#let")
    end

    test "inline sigil whose markup continues on the next lines" do
      source = ~S'''
      import AshTypst.Sigil
      x = ~TYPST"= Title
      #let s = (1, 2
      "
      '''

      error = assert_raise SyntaxError, fn -> compile!(source) end

      assert Exception.message(error) == """
             lib/example.ex:3:10: unclosed delimiter
                │
              3 │ #let s = (1, 2
                │          ~
                │\
             """

      assert location(error) == {3, 10, 3, 11}
      assert text_at(source, location(error)) == "("
    end

    test "heredoc sigil nested deep in code, with a range spanning lines" do
      source = ~S'''
      defmodule AshTypst.SigilTest.DeepHeredoc do
        import AshTypst.Sigil

        def markup(kind) do
          case kind do
            :invoice ->
              Enum.map([1], fn _ ->
                ~TYPST"""
                = Title
                #let s = "abc
                def
                """
              end)
          end
        end
      end
      '''

      error = assert_raise SyntaxError, fn -> compile!(source) end

      # The snippet underlines the first line of a multi-line range to its end.
      assert Exception.message(error) == """
             lib/example.ex:10:20: unclosed string
                 │
              10 │ #let s = "abc
                 │          ~~~~
                 │\
             """

      assert location(error) == {10, 20, 12, 11}

      assert text_at(source, location(error)) ==
               ~s("abc\n          def\n          )
    end

    test "heredoc sigil with an error in the first column of its markup" do
      source = ~S'''
      defmodule AshTypst.SigilTest.FirstColumn do
        import AshTypst.Sigil

        def markup do
          if true do
            ~TYPST"""
            = Title
            ] stray
            """
          end
        end
      end
      '''

      error = assert_raise SyntaxError, fn -> compile!(source) end

      assert Exception.message(error) == """
             lib/example.ex:8:7: unexpected closing bracket
                │
              8 │ ] stray
                │ ~
                │
               hint: try using a backslash escape: \\]\
             """

      assert location(error) == {8, 7, 8, 8}
      assert text_at(source, location(error)) == "]"
    end

    test "warning in a heredoc sigil nested in code" do
      source = ~S'''
      import AshTypst.Sigil

      for _ <- [1] do
        case :ok do
          :ok ->
            ~TYPST"""
            = Title
            Some **
            """
        end
      end
      '''

      assert {[], [%{position: {8, 12} = position}]} =
               Code.with_diagnostics(fn -> compile!(source) end)

      {line, column} = position
      assert text_at(source, {line, column, line, column + 2}) == "**"
    end

    @tag :tmp_dir
    test "compiler diagnostic for an inline sigil nested in code", %{tmp_dir: dir} do
      file = Path.join(dir, "sigil_lsp_inline.ex")

      source = ~S'''
      defmodule AshTypst.SigilTest.LspInline do
        import AshTypst.Sigil

        def markup(kind) do
          case kind do
            :invoice -> ~TYPST"= Invoice #let total = (1, 2"
          end
        end
      end
      '''

      File.write!(file, source)

      {result, _stderr} =
        ExUnit.CaptureIO.with_io(:stderr, fn ->
          Kernel.ParallelCompiler.compile([file], return_diagnostics: true)
        end)

      assert {:error, [%{position: {6, 49}, span: {6, 50}}], _warnings} = result
      assert text_at(source, {6, 49, 6, 50}) == "("
    end
  end

  describe "AshTypst.validate_syntax/1" do
    test "returns warnings for valid markup" do
      assert {:ok, [%AshTypst.Diagnostic{severity: :warning, span: span}]} =
               AshTypst.validate_syntax("= Hi **")

      assert %AshTypst.Span{start: 5, end: 7, line: 1, column: 6} = span
    end

    test "returns errors followed by warnings" do
      assert {:error, %AshTypst.CompileError{diagnostics: [error, warning]}} =
               AshTypst.validate_syntax("**\n#let x = (1, 2")

      assert %AshTypst.Diagnostic{severity: :error, message: "unclosed delimiter"} = error
      assert %AshTypst.Span{start: 12, end: 13, line: 2, column: 10} = error.span
      assert %AshTypst.Diagnostic{severity: :warning, message: "no text within stars"} = warning
    end
  end
end

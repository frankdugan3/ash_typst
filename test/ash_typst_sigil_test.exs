defmodule AshTypst.SigilTest do
  use ExUnit.Case, async: true

  doctest AshTypst.Sigil
  doctest AshTypst, only: [validate_syntax: 1]

  import AshTypst.Sigil

  @file_name "lib/example.ex"

  defp compile!(source), do: Code.compile_string(source, @file_name)

  # A syntax error is a `CompileError`, the error that the Elixir tooling and
  # the language servers know: they place it at its `file` and `line`. The
  # snippet in the message shows the column.
  defp compile_error(source) do
    error = assert_raise CompileError, fn -> compile!(source) end
    assert error.file == @file_name
    error
  end

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

    test "reports an error in an inline sigil at its line in the Elixir file" do
      error =
        compile_error(~S'''
        import AshTypst.Sigil
        x = ~TYPST"#let x = (1, 2"
        ''')

      assert Exception.message(error) == """
             lib/example.ex:2: unclosed delimiter
                │
              2 │ #let x = (1, 2
                │          ~
                │\
             """

      assert error.line == 2
    end

    test "reports an error in a heredoc sigil at its line in the Elixir file" do
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
             lib/example.ex:7: unclosed delimiter
                │
              7 │ #let x = (1, 2
                │          ~
                │\
             """

      assert error.line == 7
    end

    # Regression: an error raised as another exception than `CompileError`
    # was placed by the language servers at the `~TYPST` line (the frame of
    # the macro expansion), not at the line of the error.
    test "is a CompileError at the line of the error, not of the sigil" do
      error =
        compile_error(~S'''
        import AshTypst.Sigil

        ~TYPST"""
        = Title

        #let x = (1, 2
        """
        ''')

      assert %CompileError{line: 6} = error
    end

    # Regression: after an unclosed delimiter, Typst parses the rest of the
    # markup as code, thus one typo gave an error for each word after it.
    # Only the first error is reported, as Elixir reports its own syntax
    # errors.
    test "reports only the first error, not the errors that follow from it" do
      error =
        compile_error(~S'''
        import AshTypst.Sigil

        ~TYPST"""
        #set (document(title: "x")
        #set page(paper: "us-letter")

        = #heading

        Add a data source, then import its variable.
        """
        ''')

      assert Exception.message(error) == """
             lib/example.ex:4: expected identifier
                │
              4 │ #set (document(title: "x")
                │     ^
                │
               hint: there may not be any spaces before the argument list\
             """

      assert error.line == 4
    end

    test "reports the first of two independent errors, with its hints" do
      error =
        compile_error(~S'''
        import AshTypst.Sigil

        ~TYPST"""
        = Title
        #f(#x)
        #f(a: 1, b:)
        """
        ''')

      assert Exception.message(error) == """
             lib/example.ex:5: the character `#` is not valid in code
                │
              5 │ #f(#x)
                │    ~
                │
               hint: you are already in code mode
               hint: try removing the `#`\
             """
    end

    test "uses two-digit gutters for line numbers of two digits" do
      error =
        compile_error(~S'''
        import AshTypst.Sigil








        ~TYPST"#let x = (1, 2"
        ''')

      assert Exception.message(error) == """
             lib/example.ex:10: unclosed delimiter
                 │
              10 │ #let x = (1, 2
                 │          ~
                 │\
             """
    end

    test "counts snippet columns in codepoints, not bytes" do
      error =
        compile_error(~S'''
        import AshTypst.Sigil
        ~TYPST"= Größe #f(a:)"
        ''')

      assert Exception.message(error) == """
             lib/example.ex:2: expected expression
                │
              2 │ = Größe #f(a:)
                │              ^
                │\
             """
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
    test "produces a compiler diagnostic at the line of the error", %{tmp_dir: dir} do
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
               position: 7,
               details: {:error, %CompileError{line: 7}}
             } = diagnostic

      assert diagnostic.message =~ "unclosed delimiter"
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
             lib/example.ex:11: unclosed delimiter
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

  describe "error placement" do
    test "inline sigil nested deep in code" do
      error =
        compile_error(~S'''
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
        ''')

      assert Exception.message(error) == """
             lib/example.ex:8: unclosed delimiter
                │
              8 │ = Invoice #f(total: (1, 2)
                │             ~
                │\
             """

      assert error.line == 8
    end

    test "inline sigil preceded by other code on the same line" do
      error =
        compile_error(~S'''
        import AshTypst.Sigil
            IO.puts(String.upcase(~TYPST|#let = 1|))
        ''')

      assert Exception.message(error) == """
             lib/example.ex:2: expected pattern
                │
              2 │ #let = 1
                │     ^
                │\
             """

      assert error.line == 2
    end

    test "inline sigil whose markup continues on the next lines" do
      error =
        compile_error(~S'''
        import AshTypst.Sigil
        x = ~TYPST"= Title
        #let s = (1, 2
        "
        ''')

      assert Exception.message(error) == """
             lib/example.ex:3: unclosed delimiter
                │
              3 │ #let s = (1, 2
                │          ~
                │\
             """

      assert error.line == 3
    end

    test "heredoc sigil nested deep in code, with a range spanning lines" do
      error =
        compile_error(~S'''
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
        ''')

      # The snippet underlines the first line of a multi-line range to its end.
      assert Exception.message(error) == """
             lib/example.ex:10: unclosed string
                 │
              10 │ #let s = "abc
                 │          ~~~~
                 │\
             """

      assert error.line == 10
    end

    test "heredoc sigil with an error in the first column of its markup" do
      error =
        compile_error(~S'''
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
        ''')

      assert Exception.message(error) == """
             lib/example.ex:8: unexpected closing bracket
                │
              8 │ ] stray
                │ ~
                │
               hint: try using a backslash escape: \\]\
             """

      assert error.line == 8
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

    test "warning in an inline sigil preceded by other code on the same line" do
      source = ~S'''
      import AshTypst.Sigil
          IO.puts(String.upcase(~TYPST|= Hi **|))
      '''

      assert {[], [%{position: {2, _} = position}]} =
               Code.with_diagnostics(fn -> compile!(source) end)

      {line, column} = position
      assert text_at(source, {line, column, line, column + 2}) == "**"
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

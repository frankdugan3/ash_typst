defmodule AshTypst.WasmTest do
  use ExUnit.Case, async: true

  alias AshTypst.Wasm

  test "the identity is the package version and the Typst version of the NIF" do
    assert %{version: version, typst: typst} = Wasm.identity()
    assert version == Mix.Project.config()[:version]
    assert {:ok, %Version{}} = Version.parse(typst)
  end

  test "the default directory is priv/static/ash_typst, or the config" do
    assert Wasm.default_out() == "priv/static/ash_typst"

    Application.put_env(:ash_typst, Wasm, out: "priv/static/vendor")
    on_exit(fn -> Application.delete_env(:ash_typst, Wasm) end)
    assert Wasm.default_out() == "priv/static/vendor"
  end

  # Writes a release archive of `entries` (file name to content) into `dir`.
  defp archive!(dir, entries) do
    archive = Path.join(dir, Wasm.archive_name())
    File.mkdir_p!(dir)

    :ok =
      :erl_tar.create(
        String.to_charlist(archive),
        for({name, content} <- entries, do: {String.to_charlist(name), content}),
        [:compressed]
      )

    {"file://" <> dir, %{Wasm.archive_name() => Wasm.checksum(File.read!(archive))}}
  end

  describe "install/2" do
    @describetag :tmp_dir

    setup %{tmp_dir: tmp_dir} do
      {base_url, checksums} =
        archive!(
          Path.join(tmp_dir, "release"),
          for(file <- Wasm.files(), do: {file, "content of #{file}"})
        )

      %{base_url: base_url, checksums: checksums, out: Path.join(tmp_dir, "out")}
    end

    test "writes the files of a verified archive, and then does nothing", ctx do
      assert :ok = Wasm.install(ctx.out, base_url: ctx.base_url, checksums: ctx.checksums)

      for file <- Wasm.files() do
        assert File.read!(Path.join(ctx.out, file)) == "content of #{file}"
      end

      assert Wasm.installed?(ctx.out)
      assert :noop = Wasm.install(ctx.out, base_url: ctx.base_url, checksums: ctx.checksums)

      assert :ok =
               Wasm.install(ctx.out,
                 base_url: ctx.base_url,
                 checksums: ctx.checksums,
                 force: true
               )
    end

    test "a wrong checksum writes nothing", ctx do
      checksums = %{Wasm.archive_name() => "sha256:" <> String.duplicate("0", 64)}

      assert {:error, message} =
               Wasm.install(ctx.out, base_url: ctx.base_url, checksums: checksums)

      assert message =~ "checksum"
      refute File.exists?(ctx.out)
    end

    test "without a checksum in the package, it tells to build from source", ctx do
      assert {:error, message} = Wasm.install(ctx.out, base_url: ctx.base_url, checksums: %{})
      assert message =~ "mix ash_typst.wasm.build"
    end

    test "a file that is not of the module is not extracted", %{tmp_dir: tmp_dir} = ctx do
      {base_url, checksums} =
        archive!(
          Path.join(tmp_dir, "evil"),
          for(file <- Wasm.files() ++ ["evil.js"], do: {file, file})
        )

      assert :ok = Wasm.install(ctx.out, base_url: base_url, checksums: checksums)

      refute File.exists?(Path.join(ctx.out, "evil.js"))
    end
  end

  describe "fonts/1" do
    test "lists the distinct faces of the context, with their metadata, as JSON" do
      {:ok, ctx} = AshTypst.Context.new(ignore_system_fonts: true)
      fonts = Wasm.fonts(ctx)

      assert fonts == Enum.uniq(fonts)

      for face <- fonts do
        assert %{
                 family: family,
                 style: style,
                 weight: weight,
                 stretch: stretch,
                 math: math,
                 variable: variable,
                 axes: axes
               } = face

        assert is_binary(family)
        assert style in ["normal", "italic", "oblique"]
        assert weight in 1..1000
        assert is_float(stretch)
        assert is_boolean(math) and is_boolean(variable)

        assert Enum.all?(
                 axes,
                 &match?(%{tag: <<_::binary-size(4)>>, min: _, max: _, default: _}, &1)
               )
      end

      # The embedded fonts of Typst.
      families = fonts |> Enum.map(& &1.family) |> Enum.uniq()
      assert "Libertinus Serif" in families
      assert Enum.any?(fonts, &(&1.family == "New Computer Modern Math" and &1.math))
      assert Enum.sort(families) == Enum.sort(AshTypst.Context.font_families(ctx))

      assert fonts |> JSON.encode!() |> JSON.decode!() |> length() == length(fonts)
    end
  end

  describe "the built module" do
    # `mix ash_typst.wasm.build` writes the module. Without it, or without
    # Node, the test is skipped.
    @out Path.join(Path.expand("..", __DIR__), "priv/static/ash_typst")

    @missing (cond do
                is_nil(System.find_executable("node")) ->
                  "node is not installed"

                not File.exists?(Path.join(@out, "typst_wasm_bg.wasm")) ->
                  "run mix ash_typst.wasm.build"

                true ->
                  nil
              end)

    if @missing, do: @describetag(skip: @missing)

    test "highlights, finds syntax errors, completes fields, and has the identity of the server" do
      script = """
      import { readFileSync } from "node:fs"
      import { pathToFileURL } from "node:url"
      const [glue, wasm] = process.argv.slice(1)
      const { default: init, Analyzer } = await import(pathToFileURL(glue).href)
      await init({ module_or_path: readFileSync(wasm) })

      const analyzer = new Analyzer()
      analyzer.set_file("data.typ", '#let entries = ((memo: "a", amount: 1),)')
      const main = '#import "/data.typ": entries\\n= Title\\n#entries.first().\\n#let x = ('
      analyzer.set_file("main.typ", main)

      const cursor = main.indexOf("first().") + "first().".length
      process.stdout.write(JSON.stringify({
        highlight: analyzer.highlight("main.typ").filter((_, i) => i % 3 === 2),
        syntax: analyzer.syntax_errors("main.typ").map((d) => d.message),
        completion: (analyzer.autocomplete("main.typ", cursor, true) || { items: [] }).items.map((i) => i.label),
        build: Analyzer.build_info(),
      }))
      """

      {output, 0} =
        System.cmd("node", [
          "--input-type=module",
          "-e",
          script,
          Path.join(@out, "typst_wasm.js"),
          Path.join(@out, "typst_wasm_bg.wasm")
        ])

      result = JSON.decode!(output)

      assert "typ-heading" in result["highlight"]
      assert "typ-key" in result["highlight"]
      assert Enum.any?(result["syntax"], &(&1 =~ "unclosed"))
      assert "memo" in result["completion"]
      assert "amount" in result["completion"]

      assert result["build"] == %{
               "version" => Wasm.identity().version,
               "typst" => Wasm.identity().typst
             }
    end

    test "completes and checks the font families of the server" do
      {:ok, ctx} = AshTypst.Context.new(ignore_system_fonts: true)

      script = """
      import { readFileSync } from "node:fs"
      import { pathToFileURL } from "node:url"
      const [glue, wasm, fonts] = process.argv.slice(1)
      const { default: init, Analyzer } = await import(pathToFileURL(glue).href)
      await init({ module_or_path: readFileSync(wasm) })

      const analyzer = new Analyzer()
      const main = '#set text(font: "Nope")\\n#text(font: "libertinus serif")[a]\\n#text(font: "'
      analyzer.set_file("main.typ", main)
      const before = analyzer.syntax_errors("main.typ").map((d) => d.message)

      analyzer.set_fonts(JSON.parse(fonts))
      const completion = analyzer.autocomplete("main.typ", main.length, true) || { items: [] }

      process.stdout.write(JSON.stringify({
        before,
        after: analyzer.syntax_errors("main.typ")
          .filter((d) => d.severity === "warning")
          .map((d) => [main.slice(d.from, d.to), d.message]),
        completion: completion.items.map((i) => [i.label, i.detail]),
      }))
      """

      {output, 0} =
        System.cmd("node", [
          "--input-type=module",
          "-e",
          script,
          Path.join(@out, "typst_wasm.js"),
          Path.join(@out, "typst_wasm_bg.wasm"),
          JSON.encode!(Wasm.fonts(ctx))
        ])

      result = JSON.decode!(output)

      refute Enum.any?(result["before"], &(&1 =~ "font"))
      assert result["after"] == [[~s("Nope"), "unknown font family: Nope"]]

      assert {"Libertinus Serif", detail} =
               Enum.find_value(result["completion"], fn [label, detail] ->
                 label =~ "Libertinus Serif" && {"Libertinus Serif", detail}
               end)

      assert detail =~ "variants"
    end
  end
end

# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](Https://conventionalcommits.org) for commit guidelines.

<!-- changelog -->

## [v0.5.0](https://github.com/frankdugan3/ash_typst/compare/v0.4.0...v0.5.0) (2026-10-27)

This release focuses on **large documents**: records are really streamed,
template errors surface before the stream starts, Typst's memoization cache
is released after a render, and a render can run in a separate OS process. See the new
[Large documents](documentation/topics/large-documents.md) guide.

### Large documents

- **`read :many` streams its records.** v0.4.0 read every record at once with
  `Ash.read/2`. Records are now fetched with `Ash.stream!/2`, one page of
  `batch_size` at a time, using keyset or offset pagination.
  by Frank Polasek Dugan III

- **Preflight.** A streamed read first compiles the template against the
  first page of records, so a template error is returned before the full
  data is fetched. Disable with `preflight? false`. by Frank Polasek Dugan III

- **`AshTypst.evict_cache/1`** evicts Typst's memoization cache: the
  evaluation and layout results Typst keeps between compiles, shared by the
  whole VM, which otherwise hold a large document's memory long after its
  render. On Linux with glibc, the freed memory is then returned to the OS
  with `malloc_trim`. Emits `[:ash_typst, :cache, :evict]`. by Victor Batarse
  and Frank Polasek Dugan III

- **Streamed renders release their memory.** A render action with a streamed
  `read :many` evicts Typst's memoization cache and trims when it ends,
  whether it succeeded or failed.
  Rendering 200,000 records (11,765 pages) peaked at 5.7 GB and ended 0.3 GB
  above where it started. by Frank Polasek Dugan III

- **`isolate? true`** (or `AshTypst.Isolated.with_context/2`) runs Typst in a
  peer VM that exits after the render, so its memory never stays in your VM,
  and running out of memory fails the render instead of the server. Rendering
  50,000 records peaked at 170 MB in the calling VM instead of 1.5 GB, in the
  same time. by Frank Polasek Dugan III

### Breaking Changes:

- **`stream_with` is required on `read :many`**, with no default, and must be
  supported by the read action. Use `:keyset` for large results, or `:none`
  to keep v0.4.0's read-everything behaviour. by Frank Polasek Dugan III

- **Read configuration is validated at compile time:** undeclared `arg/1`
  references, missing or non-read actions, unknown action arguments,
  unsupported `stream_with`, and `isolate? true` with `transaction? true` and
  a streamed read. by Frank Polasek Dugan III

- **Streamed renders evict Typst's VM-wide memoization cache**, so the next
  render of any template recomputes what Typst had cached. Fonts, templates
  and assets stay loaded. by Frank Polasek Dugan III

### Features:

- `filter`, `load`, `sort` and `arguments` in reads accept `arg/1`,
  `actor/1`, `tenant/0` and `context/1` via Ash's template resolver (v0.4.0
  only resolved `^arg` in `filter`). by Frank Polasek Dugan III

- `action` and `arguments` on reads select and parameterize the read action.
  by Frank Polasek Dugan III

- The render action's tracer and `authorize?` now reach the read.
  by Frank Polasek Dugan III

- `encoding_context` on render actions, e.g.
  `encoding_context %{timezone: arg(:timezone)}`. by Frank Polasek Dugan III

### Upgrading from v0.4.0

1. Add `stream_with` to every `read :many`: `:keyset` for large results (the
   read action needs keyset pagination), `:none` to read all records at once.
2. Fix any new compile errors from the read validations.
3. For renders whose peak memory is close to what the machine can spare, set
   `isolate? true` and keep their concurrency low.

## [v0.4.0](https://github.com/frankdugan3/ash_typst/compare/v0.3.0...v0.4.0) (2026-07-17)

### Breaking Changes:

- compact encoding by dropping unselected/unloaded entirely; improve documentation for encoding by Frank Polasek Dugan III

- disable root path by default instead of assuming cwd: prevents accidental access to filesystem in templates by Frank Polasek Dugan III

### Features:

- add usage-rules by Frank Polasek Dugan III

- improve font caching, prevent memory leaks for long-running contexts by Frank Polasek Dugan III

- upgrade to Typst 0.15.1 by Frank Polasek Dugan III

## [v0.3.0](https://github.com/frankdugan3/ash_typst/compare/v0.2.0...v0.3.0) (2026-06-15)

### Breaking Changes:

- upgrade to Typst 0.15 by Frank Polasek Dugan III

## [v0.2.0](https://github.com/frankdugan3/ash_typst/compare/v0.1.1-rc.1...v0.2.0) (2026-06-07)

### Features:

- dsl: accept {otp_app, sub_path} for root and font_paths by jhlee111
- add set_virtual_file_binary for raw binary content injection by jhlee111

### Bug Fixes:

- handle empty/missing context in DateTime encode by jhlee111
- prevent BEAM crash from deep nesting by spawning compile on 64MB stack thread by jhlee111
- bugs with resource args/run by Frank Polasek Dugan III

## [v0.1.1-rc.1](https://github.com/frankdugan3/ash_typst/compare/v0.1.1-rc.0...v0.1.1-rc.1) (2026-02-26)

## [v0.1.0](https://github.com/frankdugan3/ash_typst/compare/v0.1.0...v0.1.0) (2026-02-26)

### Features:

- add Ash resource extension by Frank Polasek Dugan III

defmodule AshTypst.Diagnostic do
  @moduledoc """
  A single compiler diagnostic (error or warning) produced by Typst.

  Diagnostics appear in the `warnings` of a successful compile/export (see
  `AshTypst.CompileResult` and `AshTypst.BundleResult`) and in the `diagnostics`
  of an `AshTypst.CompileError`.

  ## Fields

    * `:severity` — `:error` or `:warning`
    * `:message` — human-readable description of the problem
    * `:span` — an `AshTypst.Span` locating the relevant source, or `nil` when
      the diagnostic is not tied to a source location
    * `:trace` — a list of `AshTypst.TraceItem` describing the chain of function
      calls that led to the diagnostic
    * `:hints` — a list of strings suggesting how to resolve the problem
  """
  defstruct [:severity, :message, :span, :trace, :hints]
end

# Elixir

Always format the code and run mix check to validate code. This package is a wrapper around the Rust library `typst` to create a safe NIF via Ruster. Assume nothing, consult the docs and code for Rustler to ensure idiomatic implementation of Rustler conventions.

## Testing

All Elixir testing belongs in the `test` folder, and must use ExUnit. This requires that the test file names end in `_test.exs`.

# Rust

For the functions which are exposed as NIFs to Elixir, ensure you are using the types provided by Rustler wherever applicable.

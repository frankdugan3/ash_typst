# Disable ANSI for stable, color-free test output.
Application.put_env(:elixir, :ansi_enabled, false)
ExUnit.start()

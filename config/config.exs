import Config

if Mix.env() == :test do
  config :elixir, :time_zone_database, Tz.TimeZoneDatabase
end

if Mix.env() in [:dev, :test] do
  config :rustler_precompiled, :force_build, ash_typst: true
end

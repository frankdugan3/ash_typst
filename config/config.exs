import Config

if Mix.env() == :test do
  config :elixir, :time_zone_database, Tz.TimeZoneDatabase
end

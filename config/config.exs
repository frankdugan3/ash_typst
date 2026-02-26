import Config

if Mix.env() == :test do
  config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase
end

if Mix.env() in [:dev, :test] do
  config :rustler_precompiled, :force_build, ash_typst: true

  config :spark, :formatter, remove_parens?: true
end

if Mix.env() == :dev do
  config :git_ops,
    mix_project: AshTypst.MixProject,
    changelog_file: "CHANGELOG.md",
    repository_url: "https://github.com/frankdugan3/ash_typst",
    manage_mix_version?: true,
    manage_readme_version: "README.md",
    version_tag_prefix: "v"
end

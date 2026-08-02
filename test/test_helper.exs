# Configure Mimic for mocking System.cmd/3 in unit tests
Mimic.copy(System)
Mimic.copy(ExQuality.Config)
Mimic.copy(ExQuality.Tools)
Mimic.copy(ExQuality.Umbrella)

# Status lines carry colour, which `IO.ANSI.format/1` emits or drops based on
# whether the output is a terminal. `mix test` from a terminal leaves it on, so
# escape codes would land in the middle of every captured line. Pin it off: the
# assertions are about what the line says, not how it is painted.
Application.put_env(:elixir, :ansi_enabled, false)

# Start ExUnit
# Note: Integration tests use fixture projects in fixtures/ to avoid infinite recursion.
# They are excluded by default for faster feedback, but can be run with:
#   mix test --include integration
ExUnit.start(exclude: [:integration])

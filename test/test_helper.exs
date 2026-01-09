# Configure Mimic for mocking System.cmd/3 in unit tests
Mimic.copy(System)
Mimic.copy(ExQuality.Tools)

# Start ExUnit
# Note: Integration tests use fixture projects in fixtures/ to avoid infinite recursion.
# They are excluded by default for faster feedback, but can be run with:
#   mix test --include integration
ExUnit.start(exclude: [:integration])

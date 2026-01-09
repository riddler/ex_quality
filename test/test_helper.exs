# Exclude integration tests by default to prevent infinite recursion
# when `mix quality` runs `mix test` which calls integration tests
# that themselves call `mix quality`
#
# To run integration tests: mix test --include integration
ExUnit.start(exclude: [:integration])

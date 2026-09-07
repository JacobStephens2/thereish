# `live` is every test that calls a provider. The suite must never spend money
# and never depend on somebody's uptime, so those are run by hand with a key:
#
#     GEMINI_API_KEY=... mix test --include live
ExUnit.start(exclude: [:live])
Ecto.Adapters.SQL.Sandbox.mode(Thereish.Repo, :manual)

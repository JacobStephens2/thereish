# PROTOTYPE image: runs the Keeper bench from the VPS. Keys come in at run time via --env-file, never baked in.
FROM hexpm/elixir:1.19.6-erlang-28.5.0.6-debian-bookworm-20260824-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates git && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV MIX_ENV=prod
RUN mix local.hex --force && mix local.rebar --force
COPY mix.exs mix.lock ./
RUN mix deps.get && mix deps.compile
COPY lib lib
RUN mix compile
ENTRYPOINT ["mix"]
CMD ["keeper.bench", "--n", "20", "--label", "vps"]

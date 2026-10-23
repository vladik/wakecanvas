ARG ELIXIR_IMAGE=hexpm/elixir:1.20.4-erlang-29.1.1-debian-bookworm-20261005-slim

FROM ${ELIXIR_IMAGE} AS build

RUN apt-get update \
    && apt-get install --yes --no-install-recommends build-essential ca-certificates git nodejs npm \
    && rm -rf /var/lib/apt/lists/*

ENV MIX_ENV=prod
WORKDIR /src
COPY . .

RUN mix local.hex --force && mix local.rebar --force

WORKDIR /src/experiences/living_gallery
RUN npm ci --ignore-scripts \
    && mix deps.get --only prod \
    && mix assets.setup \
    && mix assets.deploy \
    && mkdir -p /build/packages \
    && mix wakecanvas.package --output /build/packages/living-gallery-0.2.0.wakecanvas

WORKDIR /src/platform
RUN mix deps.get --only prod \
    && mix assets.setup \
    && mix assets.deploy \
    && mix release wake_canvas --overwrite

FROM debian:bookworm-slim AS runtime

RUN apt-get update \
    && apt-get install --yes --no-install-recommends ca-certificates curl libstdc++6 libncurses6 openssl \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 10001 wakecanvas \
    && mkdir -p /app/packages /app/seeds /data \
    && chown -R wakecanvas:wakecanvas /app /data

COPY --from=build --chown=wakecanvas:wakecanvas /src/platform/_build/prod/rel/wake_canvas/ /app/
COPY --from=build --chown=wakecanvas:wakecanvas /build/packages/ /app/packages/

USER wakecanvas
WORKDIR /app

ENV PHX_SERVER=true \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    ELIXIR_ERL_OPTIONS=+fnu \
    PORT=4000 \
    WAKECANVAS_PROFILE=hosted \
    WAKECANVAS_BIND_IP=0.0.0.0 \
    WAKECANVAS_DATA_ROOT=/data

VOLUME ["/data"]
EXPOSE 4000
HEALTHCHECK --interval=20s --timeout=5s --start-period=20s --retries=3 \
  CMD curl --fail --silent http://127.0.0.1:4000/health > /dev/null || exit 1

CMD ["/app/bin/wake_canvas", "start"]

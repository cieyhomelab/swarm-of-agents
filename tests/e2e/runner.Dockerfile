# Runner with the VPS toolset (bash, jq, curl) plus bats. The real gh CLI is
# replaced by tests/fakes/gh, which talks to the mock API.
FROM mirror.gcr.io/library/debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends bash bats ca-certificates curl jq python3 \
 && rm -rf /var/lib/apt/lists/*
RUN useradd --create-home vps
COPY --chown=vps . /work
USER vps
ENV HOME=/home/vps \
    SW_HOME=/work \
    PATH=/work/tests/fakes:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
WORKDIR /work

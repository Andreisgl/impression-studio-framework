# Copyright 2026 Andrei Segal
# SPDX-License-Identifier: Apache-2.0

# The toolchain image every build runs in: the July 2022 PS2DEV snapshot
# (docker/Dockerfile.ps2dev) plus Sony's vcl, which Tyra's VU programs need.
# vcl is a 32-bit x86 glibc binary, so the i386 runtime libraries are installed.
# It is taken from the Tyra submodule (extern/tyra/assets/vcl), which is why the
# build context is that assets folder:
#   docker build -f docker/Dockerfile -t impression/toolchain:dev extern/tyra/assets
# The host launchers (scripts/imp.*) build both images automatically when missing.
#
# The framework and Tyra sources are NOT in this image: the container mounts them
# (dev) or copies them in (SDK), and builds them on first use.

FROM impression/ps2dev:2022-07

ARG DEBIAN_FRONTEND=noninteractive
RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y libstdc++5:i386 \
    && rm -rf /var/lib/apt/lists/*

COPY vcl /usr/local/bin/vcl
RUN chmod 755 /usr/local/bin/vcl

WORKDIR /project
CMD ["sleep", "infinity"]

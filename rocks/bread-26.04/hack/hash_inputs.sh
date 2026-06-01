#!/usr/bin/env bash
# Single sha256 over everything that affects this rock's build: the
# rockcraft.yaml plus all hack/ inputs (and patches/, if present). Drives the
# .rock.stamp short-circuit in the makefile so `make build` only repacks when a
# real input changed.
#
# Stdout: hex digest only.
set -euo pipefail

cd "$(dirname "$0")/.."

# shellcheck disable=SC2046  # word-splitting of find output is intended here.
sha256sum \
    rockcraft.yaml \
    $(find hack patches -type f 2>/dev/null | sort) \
    | sha256sum | cut -d' ' -f1

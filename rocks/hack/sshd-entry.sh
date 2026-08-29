#!/bin/sh
# pebble service command for sshd in the bread rock.
#
# host keys are generated here on first boot rather than baked into the rock,
# so throwaway test containers don't all share the same keys. also ensures the
# privsep runtime dir exists. then execs sshd in the foreground (pebble manages
# the process).
set -e

mkdir -p /run/sshd
ssh-keygen -A

exec /usr/sbin/sshd -D -e

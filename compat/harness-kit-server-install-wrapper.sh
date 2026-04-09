#!/usr/bin/env bash
# ============================================================
# Compatibility Wrapper — harness-kit → slimy-harness cutover helper
#
# PURPOSE: When slimy-harness becomes the live installer, this wrapper
# sits at /home/slimy/harness-kit/server-install.sh (or in PATH) and
# forwards calls to the new slimy-harness/server-install.sh.
#
# This file is PREPARATION for cutover, NOT the cutover itself.
# Do NOT place this at the live path during this session.
#
# Cutover plan:
#   1. Ensure slimy-harness repo is cloned and at /home/slimy/slimy-harness
#   2. Replace /home/slimy/harness-kit symlink or copy wrapper to /home/slimy/harness-kit/server-install.sh
#   3. Update any crontabs or systemd services that call the old path
#   4. Update this wrapper's exec line to point to the correct location
# ============================================================

# This wrapper execs the new slimy-harness installer.
# The actual installer lives at: /home/slimy/slimy-harness/server-install.sh
#
# To activate cutover:
#   cp /home/slimy/slimy-harness/compat/harness-kit-server-install-wrapper.sh \
#      /home/slimy/harness-kit/server-install.sh
#   chmod +x /home/slimy/harness-kit/server-install.sh
#
# Or, if /home/slimy/harness-kit is itself a git clone of slimy-harness:
#   just pull and the new server-install.sh is already there.

exec /home/slimy/slimy-harness/server-install.sh "$@"

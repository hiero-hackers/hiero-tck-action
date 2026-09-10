#!/usr/bin/env bash
# Refuse to run the suite on a bash old enough to report false passes.
#
# On bash 3.2 - still the /bin/bash on macOS - bats does not fail a test when a
# non-final assertion fails, so every `[[ ... ]]` before the last line of a test
# is silently ignored. The suite reports green locally and fails on a runner.
# Runners have bash 5, so this only ever fires on a workstation.

setup_suite() {
  if ((BASH_VERSINFO[0] < 4)); then
    printf '%s\n' \
      "This suite needs bash 4 or newer; found ${BASH_VERSION}." \
      "On bash 3.2 bats silently passes a failing assertion unless it is the" \
      "last command in the test, so results here cannot be trusted." \
      "On macOS: brew install bash, then put it ahead of /bin on PATH:" \
      "  PATH=\"\$(brew --prefix)/bin:\$PATH\" bats tests" >&2
    return 1
  fi
}

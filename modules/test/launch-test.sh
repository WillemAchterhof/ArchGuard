#!/usr/bin/env bash

# ==============================================================================
#  ArchGuard Test Module
# ==============================================================================
#  modules/test/launch-test.sh
#
#  Simple module used to test the orchestrator execution flow.
#
#  Responsibilities:
#    - Print messages through the logging lib
#
#  Constraints:
#    - Definitions only at top level; all work happens in run_test.
#    - Helper functions are prefixed with test_ to avoid name clashes.
# ==============================================================================

# ==============================================================================
# Main
# ==============================================================================

run_test() {
    msg "Hello from the test module :)"

    success "Test module executed successfully."
}
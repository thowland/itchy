# Automation Mode for the UI suite. Sourced by Scripts/test.sh.
#
# XCUITest switches macOS into Automation Mode for each run, and by default the
# system asks for authentication every time it does. The dialog blocks the run
# invisibly, which reads as a hang. Signing (`make sign-setup`) does not help:
# this is a device policy, not a grant keyed on the application.
#
# So a UI run turns the policy off for its own duration and puts it back
# afterwards:
#
#   already off           left alone, and nothing is restored
#   a terminal            automationmodetool asks for your password
#   no terminal           the run stops with an explanation, unless
#                         ITCHY_UI_ALLOW_PROMPT=1 accepts the on-screen dialog
#
# Not through sudo. automationmodetool authenticates by itself, asking for the
# password of the user running it, so under sudo it asks for root's — which on
# macOS usually has no password at all.
#
# Restoring runs from the EXIT trap, so a failed or interrupted run restores
# too. Only SIGKILL escapes it; the command to restore by hand is printed
# whenever restoring does not succeed.

AUTOMATION_RESTORE=0
AUTOMATION_RESTORE_COMMAND="automationmodetool disable-automationmode-without-authentication"

automation_needs_authentication() {
  automationmodetool 2>/dev/null | grep -q "device requires user authentication"
}

# 0: ready. 1: tried and failed. 2: authentication needed and no way to ask.
automation_prepare() {
  command -v automationmodetool >/dev/null 2>&1 || return 0
  automation_needs_authentication || return 0
  [ -t 0 ] || return 2

  echo "  UI tests: Automation Mode asks for authentication on every run."
  echo "  Switching that off for this run only. It will ask for your password now,"
  echo "  and may ask again when the run ends to put it back."
  automationmodetool enable-automationmode-without-authentication || return 1
  automation_needs_authentication && return 1
  AUTOMATION_RESTORE=1
  return 0
}

automation_restore() {
  [ "$AUTOMATION_RESTORE" = "1" ] || return 0
  AUTOMATION_RESTORE=0
  if [ -t 0 ] && automationmodetool disable-automationmode-without-authentication \
    && automation_needs_authentication; then
    echo "  Automation Mode restored: it asks for authentication again"
  else
    echo "  Could not restore Automation Mode. Run: $AUTOMATION_RESTORE_COMMAND" >&2
  fi
  return 0
}

#!/usr/bin/env bash
# Strips xcodebuild's device- and simulator-plugin chatter from a build log.
#
# On a machine whose CoreSimulator framework is older than the installed Xcode,
# every single xcodebuild invocation writes sixty lines of plug-in loader
# failure to stderr — before doing the build correctly. None of it concerns this
# project: Itchy is a macOS application and never touches a simulator or a
# device. But it contains the word "error", it is longer than the real output,
# and it turns a successful `make package` into something that reads like a
# failure. It has to go, or it trains you to ignore the output entirely.
#
# This is the same judgement the Makefile already makes about naming the
# destination: a warning that reads as an error is worth removing even though
# it changes nothing about the build.
#
# What it does NOT do is hide anything that could be ours. A line is dropped
# only when it names one of Apple's device or simulator components, and the
# block that follows one is dropped only while its lines keep the shape of that
# block — an indented continuation, or one of the labels Apple's error dumps
# use. Anything else ends the block and is printed, so a compiler error
# immediately after the noise still reaches you.
#
# Reads stdin, writes stdout. The caller keeps xcodebuild's exit status.

NOISE='DVTPlugIn|DVTAssertions|DVTCoreDevice|CoreDevice|CoreSimulator|SimServiceContext|DVTDevice|DVTErrorPresenter|_knownDeviceLocators|Simulator device support disabled|Unable to load simulator devices'

# Only ever skipped while already inside a noise block.
CONT='^[[:space:]]|^(Domain|Code|Failure Reason|Recovery Suggestion|Object|Method|Thread|Details|User Info):|^--$|^Please file a bug at'

exec awk -v noise="$NOISE" -v cont="$CONT" '
  $0 ~ noise { skip = 1; next }
  skip && $0 ~ /^[[:space:]]*$/ { skip = 0; next }
  skip && $0 ~ cont { next }
  { skip = 0; print }
'

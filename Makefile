# Itchy — see docs/itchy-implementation-plan.md §2 for the sprint exit gate.
.DEFAULT_GOAL := help
SHELL := /bin/bash

SWIFTLINT := swiftlint
SWIFTFORMAT := xcrun swift-format
PACKAGES := Packages/ItchyCore Packages/ItchyServices
DD := .build/DerivedData
# Where a built application is left for a person to find. Deliberately not
# inside .build: Finder hides any directory whose name begins with a dot, so an
# app built there is invisible unless you know to press Cmd-Shift-period.
OUT := build
# Named explicitly. Without it xcodebuild prints a warning about choosing
# between arm64 and x86_64 destinations, which reads as an error.
#
# Output goes through Scripts/xcnoise.sh for the same reason: on a machine whose
# CoreSimulator is older than its Xcode, every invocation writes sixty lines of
# plug-in failure that have nothing to do with this project and contain the word
# "error". See the script for what it will and will not remove.
DEST := platform=macOS,arch=$(shell uname -m)
# The other half of a universal binary, so the shim matches the application.
ALT_ARCH := x86_64

.PHONY: help gate project regenerate test test-ui test-all sign-setup bump version lint format arch-lint coverage verify-gate app run reveal package release notarise dmg publish ship-check icon screenshots clean open

help: ## Show this help
	@grep -E '^[a-z-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

gate: lint arch-lint test coverage ## Run the full sprint exit gate (G1-G3)
	@echo ""
	@echo "Gate: G1 lint, G2 tests, G3 coverage — all green."
	@echo "G4 (acceptance criteria demonstrated) is not automatable; see the plan."

# Regenerating unconditionally rewrites the project file on every invocation,
# which invalidates Xcode's build cache and turns every test run into a full
# rebuild. So it is a file target — but depending on project.yml alone is not
# enough: adding a source file needs a regeneration too, and forgetting produces
# "cannot find X in scope" for a type that is plainly there.
#
# Directory mtimes change when a file is added or removed and not when one is
# merely edited, which is exactly the condition (D-12).
SOURCE_DIRS := $(shell find App Packages/*/Sources Packages/*/Tests Tests -type d 2>/dev/null)

Itchy.xcodeproj: project.yml $(SOURCE_DIRS)
	@command -v xcodegen >/dev/null || { echo "xcodegen not installed: brew install xcodegen"; exit 1; }
	@xcodegen generate --quiet && touch Itchy.xcodeproj && echo "project: generated"

project: Itchy.xcodeproj ## Regenerate the project when project.yml changed (D-12)

regenerate: ## Force a project regeneration
	@xcodegen generate --quiet && touch Itchy.xcodeproj && echo "project: regenerated"

open: project ## Regenerate and open in Xcode
	@open Itchy.xcodeproj

test: project ## Run tests without the UI suite (needs no permissions)
	@./Scripts/test.sh

test-ui: project ## Run the UI suite (needs macOS automation permission)
	@./Scripts/test.sh --ui-only

test-all: project ## Run everything, UI suite included
	@./Scripts/test.sh --ui

sign-setup: ## Point Debug builds at a keychain identity, so TCC stops re-asking
	@./Scripts/sign-setup.sh

bump: ## Raise the version: patch by default, PART=minor or PART=major (D-22)
	@./Scripts/bump-version.sh $(or $(PART),patch)

version: ## Print the current version
	@sed -n 's/^MARKETING_VERSION = //p' Config/Version.xcconfig

lint: ## Lint and check formatting (G1)
	@$(SWIFTLINT) lint --quiet --strict
	@$(SWIFTFORMAT) lint --recursive --strict App Packages Shim Harness 2>/dev/null \
	  || { echo "swift-format: formatting violations"; exit 1; }
	@echo "lint: ok"

format: ## Apply formatting in place
	@$(SWIFTFORMAT) format --in-place --recursive App Packages Shim Harness
	@echo "format: applied"

arch-lint: ## Check the four architectural invariants
	@./Scripts/arch-lint.sh

coverage: project ## Measure coverage against the 80% floor (G3)
	@./Scripts/coverage.sh

verify-gate: ## Prove the gates fail when they should
	@./Scripts/verify-gates.sh

app: project ## Build the application bundle into ./build
	@set -o pipefail; xcodebuild -project Itchy.xcodeproj -scheme Itchy -configuration Release \
	  -destination "$(DEST)" -derivedDataPath $(DD) build -quiet 2>&1 | ./Scripts/xcnoise.sh
	@# The shim ships beside the application, universal like it, and is built
	@# by SwiftPM rather than the Xcode target because it links none of the
	@# application's code. `--show-bin-path` rather than a hard-coded directory:
	@# SwiftPM has moved it before.
	@cd Shim && swift build -c release --arch arm64 --arch $(ALT_ARCH) >/dev/null 2>&1
	@mkdir -p $(OUT)
	@rm -rf $(OUT)/Itchy.app
	@cp -R $(DD)/Build/Products/Release/Itchy.app $(OUT)/Itchy.app
	@cp "$$(cd Shim && swift build -c release --arch arm64 --arch $(ALT_ARCH) --show-bin-path 2>/dev/null)/itchy-mcp" \
	  $(OUT)/Itchy.app/Contents/MacOS/itchy-mcp
	@# Re-sealed, because a binary added after the bundle was signed is not
	@# covered by its signature. Ad-hoc here to match the Release default in
	@# project.yml; `make release` signs the same arrangement with a Developer ID.
	@codesign --force --sign - $(OUT)/Itchy.app/Contents/MacOS/itchy-mcp
	@codesign --force --sign - $(OUT)/Itchy.app
	@echo "app: $(CURDIR)/$(OUT)/Itchy.app"
	@echo "     open it with 'make run', or 'make reveal' to show it in Finder"

run: app ## Build and launch the application
	@open $(OUT)/Itchy.app && echo "run: launched (look for the cat in the menubar)"

reveal: app ## Build and show the application in Finder
	@open -R $(OUT)/Itchy.app

package: app ## Build a DMG from the current build (no Developer ID needed)
	@./Scripts/release.sh package

release: ## Build a Developer ID signed, hardened release (NFR-4.2)
	@./Scripts/release.sh build

notarise: ## Notarise and staple the release build
	@./Scripts/release.sh notarise

dmg: ## Package a signed, stapled DMG
	@./Scripts/release.sh dmg

publish: ## Draft a GitHub release from the current DMG; PUBLISH=1 to go live
	@./Scripts/release.sh publish

ship-check: ## Report whether this machine can produce a shippable build
	@./Scripts/release.sh check

screenshots: project ## Regenerate docs/images from the running application (needs automation)
	@./Scripts/screenshots.sh

icon: ## Regenerate the app icon from the cat.fill symbol
	@swift Scripts/make-appicon.swift && echo "icon: regenerated"

clean: ## Remove build products and the generated project
	@rm -rf .build Packages/*/.build Harness/.build Tests/Fixtures/*/.build $(DD) $(OUT) Itchy.xcodeproj
	@echo "clean: done"

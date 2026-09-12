# Itchy — see docs/itchy-implementation-plan.md §2 for the sprint exit gate.
.DEFAULT_GOAL := help
SHELL := /bin/bash

SWIFTLINT := swiftlint
SWIFTFORMAT := xcrun swift-format
PACKAGES := Packages/ItchyCore Packages/ItchyServices
DD := .build/DerivedData

.PHONY: help gate project regenerate test lint format arch-lint coverage verify-gate app release notarise dmg ship-check icon clean open

help: ## Show this help
	@grep -E '^[a-z-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

gate: lint arch-lint test coverage ## Run the full sprint exit gate (G1-G3)
	@echo ""
	@echo "Gate: G1 lint, G2 tests, G3 coverage — all green."
	@echo "G4 (acceptance criteria demonstrated) is not automatable; see the plan."

# Regenerating unconditionally rewrites the project file on every invocation,
# which invalidates Xcode's build cache and turns every test run into a full
# rebuild. As a file target it regenerates only when project.yml changed (D-12).
Itchy.xcodeproj: project.yml
	@command -v xcodegen >/dev/null || { echo "xcodegen not installed: brew install xcodegen"; exit 1; }
	@xcodegen generate --quiet && touch Itchy.xcodeproj && echo "project: generated"

project: Itchy.xcodeproj ## Regenerate the project when project.yml changed (D-12)

regenerate: ## Force a project regeneration
	@xcodegen generate --quiet && touch Itchy.xcodeproj && echo "project: regenerated"

open: project ## Regenerate and open in Xcode
	@open Itchy.xcodeproj

test: project ## Run all tests, with hard time limits
	@./Scripts/test.sh

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

app: project ## Build the application bundle
	@xcodebuild -project Itchy.xcodeproj -scheme Itchy -configuration Release \
	  -derivedDataPath $(DD) build -quiet && echo "app: built"

release: ## Build a Developer ID signed, hardened release (NFR-4.2)
	@./Scripts/release.sh build

notarise: ## Notarise and staple the release build
	@./Scripts/release.sh notarise

dmg: ## Package a signed, stapled DMG
	@./Scripts/release.sh dmg

ship-check: ## Report whether this machine can produce a shippable build
	@./Scripts/release.sh check

icon: ## Regenerate the app icon from the cat.fill symbol
	@swift Scripts/make-appicon.swift && echo "icon: regenerated"

clean: ## Remove build products and the generated project
	@rm -rf .build Packages/*/.build Harness/.build Tests/Fixtures/*/.build $(DD) Itchy.xcodeproj
	@echo "clean: done"

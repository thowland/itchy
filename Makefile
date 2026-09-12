# Itchy — see docs/itchy-implementation-plan.md §2 for the sprint exit gate.
.DEFAULT_GOAL := help
SHELL := /bin/bash

SWIFTLINT := swiftlint
SWIFTFORMAT := xcrun swift-format
PACKAGES := Packages/ItchyCore Packages/ItchyServices
DD := .build/DerivedData

.PHONY: help gate project test lint format arch-lint coverage verify-gate app notarise dmg clean open

help: ## Show this help
	@grep -E '^[a-z-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

gate: lint arch-lint test coverage ## Run the full sprint exit gate (G1-G3)
	@echo ""
	@echo "Gate: G1 lint, G2 tests, G3 coverage — all green."
	@echo "G4 (acceptance criteria demonstrated) is not automatable; see the plan."

project: ## Regenerate Itchy.xcodeproj from project.yml (D-12)
	@command -v xcodegen >/dev/null || { echo "xcodegen not installed: brew install xcodegen"; exit 1; }
	@xcodegen generate --quiet && echo "project: generated"

open: project ## Regenerate and open in Xcode
	@open Itchy.xcodeproj

test: project ## Run all tests (packages, harness, app target)
	@for p in $(PACKAGES); do \
	  echo "==> $$p"; \
	  ( cd $$p && swift test ) || exit 1; \
	done
	@echo "==> Harness (build only; not shipped, not measured)"
	@( cd Harness && swift build ) >/dev/null || exit 1
	@echo "==> app target"
	@set -o pipefail; xcodebuild test -project Itchy.xcodeproj -scheme Itchy \
	  -derivedDataPath $(DD) -quiet 2>&1 | grep -vE "^$$" | tail -5

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

notarise: app ## Sign, notarise and staple
	@echo "Not implemented until Sprint 5 (NFR-4.2)."; exit 1

dmg: notarise ## Package a signed DMG
	@echo "Not implemented until Sprint 5."; exit 1

clean: ## Remove build products and the generated project
	@rm -rf .build Packages/*/.build Harness/.build Tests/Fixtures/*/.build $(DD) Itchy.xcodeproj
	@echo "clean: done"

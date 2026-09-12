# Itchy — see docs/itchy-implementation-plan.md §2 for the sprint exit gate.
.DEFAULT_GOAL := help
SHELL := /bin/bash

SWIFTLINT := swiftlint
SWIFTFORMAT := xcrun swift-format
PACKAGES := Packages/ItchyCore Packages/ItchyServices

.PHONY: help gate test lint format arch-lint coverage verify-gate app notarise dmg clean

help: ## Show this help
	@grep -E '^[a-z-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

gate: lint arch-lint test coverage ## Run the full sprint exit gate (G1-G3)
	@echo ""
	@echo "Gate: G1 lint, G2 tests, G3 coverage — all green."
	@echo "G4 (acceptance criteria demonstrated) is not automatable; see the plan."

test: ## Run all tests
	@for p in $(PACKAGES); do \
	  echo "==> $$p"; \
	  ( cd $$p && swift test ) || exit 1; \
	done

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

coverage: ## Measure coverage against the 80% floor (G3)
	@./Scripts/coverage.sh

verify-gate: ## Prove the gates fail when they should
	@./Scripts/verify-gates.sh

app: ## Build the application bundle
	@test -d Itchy.xcodeproj || { \
	  echo "No Itchy.xcodeproj yet — see docs/decisions/D-12-xcode-project.md"; exit 1; }
	@xcodebuild -project Itchy.xcodeproj -scheme Itchy -configuration Release build

notarise: app ## Sign, notarise and staple
	@echo "Not implemented until Sprint 5 (NFR-4.2)."; exit 1

dmg: notarise ## Package a signed DMG
	@echo "Not implemented until Sprint 5."; exit 1

clean: ## Remove build products
	@rm -rf .build Packages/*/.build Tests/Fixtures/*/.build DerivedData
	@echo "clean: done"

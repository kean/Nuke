.PHONY: ci ci-list test build lint spm help

CI := bash .scripts/ci.sh

## Run every CI job (build, test, lint) for every scheme and platform
ci:
	@$(CI)

## List every job, group, and action
ci-list:
	@$(CI) --list

## Run one job, group, or action, e.g. make ci-macos or make ci-test-nuke-ios
ci-%:
	@$(CI) $*

## Run all unit tests (iOS, tvOS, macOS)
test:
	@$(CI) test

## Compile every scheme for every platform (no tests)
build:
	@$(CI) build

## Run SwiftLint
lint:
	@$(CI) lint

## Build the SPM package including tests
spm:
	@$(CI) spm

## Show available targets
help:
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@awk '/^## /{desc=substr($$0,4); next} /^[a-zA-Z_%-]+:/{printf "  %-16s %s\n", $$1, desc; desc=""}' $(MAKEFILE_LIST)
	@echo ""

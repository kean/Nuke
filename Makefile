.PHONY: ci ci-list test build lint spm help

SCRIPTS := .scripts

## Run every CI job (build, test, lint) for every scheme and platform
ci:
	@bash $(SCRIPTS)/ci.sh

## List all CI groups and job IDs
ci-list:
	@bash $(SCRIPTS)/ci.sh --list

## Run one GitHub job's worth of work, e.g. make ci-group-ios-core
ci-group-%:
	@bash $(SCRIPTS)/ci.sh --group $*

## Run a single CI job by ID, e.g. make ci-test-nuke-ios (see: make ci-list)
ci-%:
	@bash $(SCRIPTS)/ci.sh $*

## Run all unit tests (iOS, macOS, tvOS)
test:
	@bash $(SCRIPTS)/ci.sh --group ios-core
	@bash $(SCRIPTS)/ci.sh --group ios-ui
	@bash $(SCRIPTS)/ci.sh --group macos
	@bash $(SCRIPTS)/ci.sh --group tvos

## Compile every scheme for every platform (no tests)
build:
	@bash $(SCRIPTS)/ci.sh --group platforms

## Run SwiftLint
lint:
	@bash $(SCRIPTS)/ci.sh lint

## Build the SPM package including tests
spm:
	@bash $(SCRIPTS)/ci.sh spm-build

## Show available targets
help:
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@awk '/^## /{desc=substr($$0,4); next} /^[a-zA-Z_%-]+:/{printf "  %-16s %s\n", $$1, desc; desc=""}' $(MAKEFILE_LIST)
	@echo ""

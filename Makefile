.PHONY: ci ci-list test test-one build lint spm snippets llms release-check release docs deploy-docs help

CI := bash .scripts/ci.sh

SCHEME ?= Nuke
PLATFORM ?= macOS

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

## Run one test and print how many ran, e.g. make test-one TEST=ImageRequestTests/testInit [SCHEME=NukeUI] [PLATFORM=iOS]
test-one:
	@bash .scripts/test-one.sh "$(TEST)" "$(SCHEME)" "$(PLATFORM)"

## Compile every scheme for every platform (no tests)
build:
	@$(CI) build

## Run SwiftLint
lint:
	@$(CI) lint

## Build the package with SwiftPM
spm:
	@$(CI) spm

## Compile the code samples from the DocC articles
snippets:
	@$(CI) snippets

## Regenerate llms.txt, llms-full.txt, and llms-api.txt (a step of the release, not of a pull request)
llms:
	@python3 .scripts/generate-llms.py

## Fail if the generated llms files are stale, to run before tagging a release
release-check:
	@python3 .scripts/generate-llms.py --check --fresh

## Cut a release one confirmed step at a time, e.g. make release VERSION=14.0.0 (needs a terminal)
release:
	@python3 .scripts/release.py "$(VERSION)"

## Build the site for kean-docs.github.io in .build/docs, or in OUTPUT. Deploys nothing
docs:
	@bash .scripts/publish-docs.sh $(OUTPUT)

## Build the docs and commit them to the kean-docs.github.io checkout, at a tag. ARGS="--push" pushes
deploy-docs:
	@bash .scripts/deploy-docs.sh $(ARGS)

## Show available targets
help:
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@awk '/^## /{desc=substr($$0,4); next} /^[a-zA-Z_%-]+:/{printf "  %-16s %s\n", $$1, desc; desc=""}' $(MAKEFILE_LIST)
	@echo ""

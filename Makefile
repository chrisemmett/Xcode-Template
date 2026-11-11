# Day-to-day commands. CI runs exactly these targets, so "green locally" means
# "green on CI". Run `make help` for the list.

APP          ?= {{APP_NAME}}
PROJECT      ?= $(APP).xcodeproj
SCHEME       ?= $(APP)
UI_SCHEME    ?= $(APP)UITests
DERIVED_DATA ?= build/DerivedData
# The deployment target, read from project.yml (options.deploymentTarget.iOS) so
# nothing has to be kept in step by hand. The simulator picker skips runtimes below it.
MIN_IOS      ?= $(shell awk -F'"' '/^    iOS:/ {print $$2; exit}' project.yml)
# Local Swift packages that build on plain `swift test` (Foundation only, no
# UIKit/SwiftUI): the fast, deterministic half of the gate, and the half a cloud
# Claude session without Xcode can run. Space-separated paths; empty to skip.
CORE_PACKAGES ?= $(wildcard Packages/*Core)
# Unsigned simulator builds: CI never needs a signing identity to build and test.
# A target whose tests need entitlements at runtime (CloudKit's container ID,
# say) must be signed instead: drop CODE_SIGNING_ALLOWED=NO for that scheme.
XCODEBUILD    = xcodebuild -project $(PROJECT) -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO

.PHONY: help bootstrap generate open lint format check check-lld check-store-metadata check-xcode test-scripts \
        test test-core test-app test-ui build clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  %-22s %s\n", $$1, $$2}'

bootstrap: ## Install tools (Brewfile, after asking), create Config/Local.xcconfig, generate the project
	@if [ -z "$$CI" ] && [ "$${YES:-}" != 1 ]; then \
	  echo "make bootstrap installs these Homebrew packages on $$(hostname -s 2>/dev/null || hostname):"; \
	  grep -vE '^[[:space:]]*(#|$$)' Brewfile | sed 's/^/  /'; \
	  printf 'Install them on this Mac? [y/N]: '; read ans; \
	  case "$$ans" in y|Y|yes) ;; *) echo "Nothing installed."; exit 1 ;; esac; \
	fi
	brew bundle --no-upgrade
	@test -f Config/Local.xcconfig || cp Config/Local.example.xcconfig Config/Local.xcconfig
	$(MAKE) generate

generate: ## Generate the Xcode project from project.yml (the .xcodeproj is not committed)
	xcodegen generate

open: generate ## Generate and open the project in Xcode
	open $(PROJECT)

lint: ## SwiftLint (strict: warnings fail) and SwiftFormat in check mode
	swiftlint lint --strict --quiet
	swiftformat --lint .

format: ## Apply SwiftFormat, then SwiftLint's autocorrections
	swiftformat .
	swiftlint lint --fix --quiet

# Python and shell only, no Xcode: runs on the docs-only fast path too.
check: check-lld check-store-metadata test-scripts ## Cheap checks: LLD todo/done, App Store metadata, the CI scripts' self-tests

check-lld: ## No LLD number in both todo/ and done/
	scripts/check_lld_todo_done.sh

check-store-metadata: ## App Store text within App Store Connect's limits
	python3 -B scripts/check_store_metadata.py

check-xcode: ## The runner's Xcode against .xcode-version (major mismatch fails, drift warns)
	scripts/check_xcode_pin.sh major

test-scripts: ## Self-tests of the CI scripts
	python3 -B -m unittest discover -s scripts -p 'test_*.py'

test: test-core test-app ## Every test on the merge gate

test-core: ## Platform-neutral packages with `swift test` (macOS and Linux)
	@for pkg in $(CORE_PACKAGES); do echo "swift test --package-path $$pkg"; swift test --package-path "$$pkg" || exit 1; done

test-app: generate ## The app's unit tests on an iPhone simulator at the deployment floor
	MIN_OS=$(MIN_IOS) XCODEBUILD="$(XCODEBUILD)" RESULT_BUNDLE=build/$(SCHEME).xcresult \
		scripts/xctest.sh iOS $(SCHEME)
# More platforms: one line each, for example
#	MIN_OS=$(MIN_WATCHOS) XCODEBUILD="$(XCODEBUILD)" scripts/xctest.sh watchOS $(APP)Watch
#	MIN_OS=$(MIN_TVOS)    XCODEBUILD="$(XCODEBUILD)" scripts/xctest.sh tvOS $(APP)-tvOS

test-ui: generate ## The XCUITest scheme, on an erased simulator (nightly, off the gate)
	SIM_ERASE=1 MIN_OS=$(MIN_IOS) XCODEBUILD="$(XCODEBUILD)" RESULT_BUNDLE=build/$(UI_SCHEME).xcresult \
		scripts/xctest.sh iOS $(UI_SCHEME)

build: generate ## Build the app for the simulator, without tests
	$(XCODEBUILD) -scheme $(SCHEME) -destination 'generic/platform=iOS Simulator' build

clean: ## Remove build output and the generated project
	rm -rf build $(PROJECT) Packages/*/.build

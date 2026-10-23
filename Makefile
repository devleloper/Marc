PROJECT := Marc.xcodeproj
SCHEME := Marc
PACKAGE := Packages/MarcKit
DERIVED := build/DerivedData
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS' -derivedDataPath $(DERIVED)
BEAUTIFY := $(shell command -v xcbeautify >/dev/null 2>&1 && echo "| xcbeautify" || echo "")

.PHONY: bootstrap tools project build run test test-package test-ui screenshots lint format clean

bootstrap:
	brew bundle --file=Brewfile
	$(MAKE) project

# The exact tool versions CI uses, installed into .tools/bin.
tools:
	scripts/install-tools.sh

project:
	xcodegen generate --quiet

build: project
	set -o pipefail && $(XCODEBUILD) -configuration Debug build $(BEAUTIFY)

run: build
	open "$(DERIVED)/Build/Products/Debug/Marc.app"

test: test-package test-ui

test-package:
	swift test --package-path $(PACKAGE)

test-ui: project
	set -o pipefail && $(XCODEBUILD) -configuration Debug test $(BEAUTIFY)

# README screenshots from the demo workspace (loads public web pages).
screenshots: project
	rm -rf build/Screenshots.xcresult
	set -o pipefail && TEST_RUNNER_MARC_SCREENSHOTS=1 $(XCODEBUILD) -configuration Debug \
		-resultBundlePath build/Screenshots.xcresult -only-testing:MarcUITests/ScreenshotTests test $(BEAUTIFY)
	scripts/export-screenshots.sh build/Screenshots.xcresult docs/images

lint:
	swiftformat --lint .
	swiftlint lint --strict --quiet

format:
	swiftformat .
	swiftlint lint --fix --quiet

clean:
	rm -rf build $(PACKAGE)/.build $(PROJECT)

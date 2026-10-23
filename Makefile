PROJECT := Marc.xcodeproj
SCHEME := Marc
PACKAGE := Packages/MarcKit
DERIVED := build/DerivedData
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS' -derivedDataPath $(DERIVED)
BEAUTIFY := $(shell command -v xcbeautify >/dev/null 2>&1 && echo "| xcbeautify" || echo "")

.PHONY: bootstrap project build run test test-package test-ui lint format clean

bootstrap:
	brew bundle --file=Brewfile
	$(MAKE) project

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

lint:
	swiftformat --lint .
	swiftlint lint --strict --quiet

format:
	swiftformat .
	swiftlint lint --fix --quiet

clean:
	rm -rf build $(PACKAGE)/.build $(PROJECT)

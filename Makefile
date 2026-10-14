# RunCat — menu bar system monitor. Builds with the command-line tools only (no Xcode).

APP_NAME     := RunCat
BUNDLE_ID    := com.jackallen.runcat
SIGN_ID      := RunCat Local
VERSION      := 0.1.0
BUILD_DIR    := build
APP          := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS     := $(APP)/Contents

# The CLT ships both the macOS 26.5 and 27.0 SDKs and defaults to 27.0, whose SwiftUI relies on
# a macro plugin the CLT doesn't include. Pin the SDK that matches the installed OS.
SDK          := /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
SWIFT_FLAGS  := --sdk $(SDK)

# Likewise the Swift Testing macro plugin lives in a subdirectory the build system doesn't search.
TESTING_PLUGIN := /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
TEST_FLAGS     := $(SWIFT_FLAGS) -Xswiftc -load-plugin-library -Xswiftc $(TESTING_PLUGIN)

RELEASE_BIN  = $(shell swift build -c release $(SWIFT_FLAGS) --show-bin-path 2>/dev/null)/$(APP_NAME)

.PHONY: build test release app run screenshots install clean

build:
	swift build $(SWIFT_FLAGS)

test:
	swift test $(TEST_FLAGS)

release:
	swift build -c release $(SWIFT_FLAGS)

app: release
	rm -rf "$(APP)"
	mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"
	cp "$(RELEASE_BIN)" "$(CONTENTS)/MacOS/$(APP_NAME)"
	sed -e 's/@VERSION@/$(VERSION)/g' -e 's/@BUNDLE_ID@/$(BUNDLE_ID)/g' Resources/Info.plist > "$(CONTENTS)/Info.plist"
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$(CONTENTS)/Resources/"; fi
	codesign --force --sign "$(SIGN_ID)" --identifier "$(BUNDLE_ID)" --options runtime \
		--entitlements Resources/RunCat.entitlements "$(APP)"
	codesign --verify --deep --strict "$(APP)"
	@echo "Built $(APP)"

run: app
	pkill -x $(APP_NAME) || true
	open "$(APP)"

# Renders the indicator and panel to PNGs in build/screenshots without Screen Recording permission.
screenshots: app
	pkill -x $(APP_NAME) || true
	rm -rf "$(BUILD_DIR)/screenshots"
	"$(CONTENTS)/MacOS/$(APP_NAME)" -Screenshot "$(PWD)/$(BUILD_DIR)/screenshots"
	@ls "$(BUILD_DIR)/screenshots"

install: app
	pkill -x $(APP_NAME) || true
	rm -rf "/Applications/$(APP_NAME).app"
	cp -R "$(APP)" /Applications/
	open "/Applications/$(APP_NAME).app"

clean:
	rm -rf .build $(BUILD_DIR)

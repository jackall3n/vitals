# RunCat — menu bar system monitor. Builds with the command-line tools only (no Xcode).

APP_NAME     := RunCat
BUNDLE_ID    := com.jackallen.runcat
SIGN_ID      := RunCat Local
VERSION      := 0.1.0
BUILD_DIR    := build
APP          := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS     := $(APP)/Contents
RELEASE_BIN  := $(shell swift build -c release --show-bin-path 2>/dev/null)/$(APP_NAME)

# The CLT ships the Swift Testing macro plugin in a subdirectory the default build system
# doesn't search, so point the compiler at it explicitly.
TESTING_PLUGIN := /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
TEST_FLAGS     := -Xswiftc -load-plugin-library -Xswiftc $(TESTING_PLUGIN)

.PHONY: build test release app run install clean

build:
	swift build

test:
	swift test $(TEST_FLAGS)

release:
	swift build -c release

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

install: app
	pkill -x $(APP_NAME) || true
	rm -rf "/Applications/$(APP_NAME).app"
	cp -R "$(APP)" /Applications/
	open "/Applications/$(APP_NAME).app"

clean:
	rm -rf .build $(BUILD_DIR)

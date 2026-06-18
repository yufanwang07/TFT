APP_NAME := TFTOverlay
BUILD_DIR := .build
SOURCE := Sources/TFTOverlay/main.m
APP_DIR := $(BUILD_DIR)/$(APP_NAME).app
BIN := $(APP_DIR)/Contents/MacOS/$(APP_NAME)

.PHONY: all run logs clean

all: $(BIN)

$(BIN): $(SOURCE)
	mkdir -p "$(APP_DIR)/Contents/MacOS"
	mkdir -p "$(APP_DIR)/Contents/Resources"
	clang -fobjc-arc -framework AppKit -framework Foundation "$(SOURCE)" -o "$(BIN)"
	/usr/libexec/PlistBuddy -c "Clear dict" "$(APP_DIR)/Contents/Info.plist" 2>/dev/null || true
	/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $(APP_NAME)" "$(APP_DIR)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string local.tft.overlay" "$(APP_DIR)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Add :CFBundleName string $(APP_NAME)" "$(APP_DIR)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$(APP_DIR)/Contents/Info.plist"

run: all
	open "$(APP_DIR)"

logs:
	open "$(HOME)/Library/Application Support/TFTOverlay/Captures"

clean:
	rm -rf "$(BUILD_DIR)"

APP_NAME := TFTOverlay
BUILD_DIR := .build
SOURCE := Sources/TFTOverlay/main.m
APP_DIR := $(BUILD_DIR)/$(APP_NAME).app
BIN := $(APP_DIR)/Contents/MacOS/$(APP_NAME)
DETECTED_CODESIGN_IDENTITY := $(shell security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '/Apple Development|Mac Developer|Developer ID Application|3rd Party Mac Developer Application/ { print $$2; exit }')
CODESIGN_IDENTITY ?= $(DETECTED_CODESIGN_IDENTITY)

TFT_SET ?= 17
METATFT_UNIT ?= MissFortune
PREVIEW_UNIT ?= Miss Fortune
PREVIEW_OUT ?= offline-previews/item-recommendations-preview.png

.PHONY: all bundle-data run run-open logs scrape scrape-metatft scrape-metatft-debug scrape-gods refresh-data analyze-logs offline-preview offline-item-preview signing-identities clean

all: $(BIN) bundle-data

$(BIN): $(SOURCE) Makefile
	mkdir -p "$(APP_DIR)/Contents/MacOS"
	mkdir -p "$(APP_DIR)/Contents/Resources"
	clang -fobjc-arc -framework AppKit -framework Foundation -framework Vision -framework CoreGraphics -framework ApplicationServices -framework ScreenCaptureKit -framework CoreMedia -framework CoreImage -framework CoreVideo -framework Accelerate "$(SOURCE)" -o "$(BIN)"

bundle-data: $(BIN)
	mkdir -p "$(APP_DIR)/Contents/Resources"
	if [ -f "data/tftacademy/latest.json" ]; then cp "data/tftacademy/latest.json" "$(APP_DIR)/Contents/Resources/tftacademy-latest.json"; fi
	if [ -f "data/metatft/latest.json" ]; then cp "data/metatft/latest.json" "$(APP_DIR)/Contents/Resources/metatft-latest.json"; fi
	if [ -f "data/metatft/god-tiers.json" ]; then cp "data/metatft/god-tiers.json" "$(APP_DIR)/Contents/Resources/metatft-god-tiers.json"; fi
	if [ -d "data/tftacademy/champions" ]; then rm -rf "$(APP_DIR)/Contents/Resources/champions"; cp -R "data/tftacademy/champions" "$(APP_DIR)/Contents/Resources/champions"; fi
	if [ -d "data/tftacademy/items" ]; then rm -rf "$(APP_DIR)/Contents/Resources/items"; cp -R "data/tftacademy/items" "$(APP_DIR)/Contents/Resources/items"; fi
	if [ -d "data/tftacademy/traits" ]; then rm -rf "$(APP_DIR)/Contents/Resources/traits"; cp -R "data/tftacademy/traits" "$(APP_DIR)/Contents/Resources/traits"; fi
	if [ -d "tft_item/items" ]; then rm -rf "$(APP_DIR)/Contents/Resources/item-templates"; cp -R "tft_item/items" "$(APP_DIR)/Contents/Resources/item-templates"; fi
	/usr/libexec/PlistBuddy -c "Clear dict" "$(APP_DIR)/Contents/Info.plist" 2>/dev/null || true
	/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $(APP_NAME)" "$(APP_DIR)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string local.tft.overlay" "$(APP_DIR)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Add :CFBundleName string $(APP_NAME)" "$(APP_DIR)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$(APP_DIR)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 1" "$(APP_DIR)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 0.1" "$(APP_DIR)/Contents/Info.plist"
	if [ -n "$(CODESIGN_IDENTITY)" ]; then \
		codesign --force --deep --sign "$(CODESIGN_IDENTITY)" --identifier local.tft.overlay "$(APP_DIR)"; \
	else \
		rm -rf "$(APP_DIR)/Contents/_CodeSignature"; \
		printf '%s\n' 'Built without a stable codesigning identity. macOS may ask for Screen Recording again after rebuilds.'; \
	fi

run: all
	"$(BIN)" >/tmp/TFTOverlay.log 2>&1 &

run-open: all
	open "$(APP_DIR)"

logs:
	open "$(HOME)/Library/Application Support/TFTOverlay/Captures"

scrape:
	node backend/tftacademy-scraper.js

scrape-metatft:
	node backend/metatft-scraper.js

scrape-metatft-debug:
	METATFT_DUMP_HTML=1 METATFT_DUMP_UNITS="$(METATFT_UNIT)" METATFT_UNITS="$(METATFT_UNIT)" node backend/metatft-scraper.js

scrape-gods:
	node backend/metatft-gods-scraper.js

refresh-data:
	TFT_FORCE_REFRESH=1 TFT_SET="$(TFT_SET)" node backend/tftacademy-scraper.js --force
	TFT_FORCE_REFRESH=1 node backend/metatft-scraper.js --force
	TFT_FORCE_REFRESH=1 node backend/metatft-gods-scraper.js --force
	$(MAKE) bundle-data
	@printf '%s\n' 'Fresh patch data scraped and bundled into $(APP_DIR).'

analyze-logs:
	python3 tools/analyze_capture.py

offline-preview:
	python3 tools/offline_overlay_preview.py

offline-item-preview:
	python3 tools/offline_overlay_preview.py $(if $(PREVIEW_IMAGE),"$(PREVIEW_IMAGE)",) --item-recommendations "$(PREVIEW_UNIT)" --hide-augments --hide-debug --out "$(PREVIEW_OUT)"

signing-identities:
	security find-identity -v -p codesigning

clean:
	rm -rf "$(BUILD_DIR)"

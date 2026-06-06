APP_NAME    := QuartzFocus
BUNDLE_ID   := com.lumither.QuartzFocus
APP_BUNDLE  := .build/release/$(APP_NAME).app
DMG_STAGING := .build/dmg
DMG_PATH    := .build/$(APP_NAME).dmg

.PHONY: all
all: app

.PHONY: app
app:
	./scripts/build-app.sh

.PHONY: install
install: app
	rm -rf $(DMG_STAGING)
	mkdir -p $(DMG_STAGING)
	cp -R $(APP_BUNDLE) $(DMG_STAGING)/
	ln -s /Applications $(DMG_STAGING)/Applications
	rm -f $(DMG_PATH)
	hdiutil create -volname "$(APP_NAME)" -srcfolder $(DMG_STAGING) -ov -format UDZO $(DMG_PATH)
	rm -rf $(DMG_STAGING)
	open $(DMG_PATH)

.PHONY: icon
icon:
	swift scripts/generate-icon.swift

.PHONY: build
build:
	swift build

.PHONY: release
release:
	swift build -c release

.PHONY: test
test:
	swift test

.PHONY: fmt
fmt:
	swift format -i -r Sources Tests scripts Package.swift

.PHONY: run
run:
	swift run $(APP_NAME)

.PHONY: open
open: app
	open $(APP_BUNDLE)

.PHONY: probe-mc
probe-mc:
	swift scripts/probe-mission-control.swift

.PHONY: wipe-tcc
wipe-tcc:
	-killall $(APP_NAME) 2>/dev/null
	tccutil reset Accessibility $(BUNDLE_ID)
	@echo "TCC Accessibility reset for $(BUNDLE_ID). Re-grant on next launch."

.PHONY: wipe-config
wipe-config:
	-killall $(APP_NAME) 2>/dev/null
	defaults delete $(BUNDLE_ID) 2>/dev/null || true
	defaults delete $(APP_NAME) 2>/dev/null || true
	@echo "User defaults cleared for $(BUNDLE_ID). Defaults will reset on next launch."

.PHONY: clean
clean:
	swift package clean
	rm -rf .build
	rm -rf App/AppIcon.iconset
	rm -f App/AppIcon.icns

.PHONY: help
help:
	@echo "QuartzFocus — make targets"
	@echo ""
	@echo "  make app      Build, assemble, and ad-hoc sign the .app bundle (default)"
	@echo "  make icon     Regenerate App/AppIcon.icns"
	@echo "  make install  Build app and open a DMG installer (drag to Applications)"
	@echo "  make open     make app, then open the bundle"
	@echo ""
	@echo "  make build    swift build (debug)"
	@echo "  make release  swift build -c release"
	@echo "  make test     swift test"
	@echo "  make fmt      Format Swift sources in place (swift format)"
	@echo "  make run      swift run $(APP_NAME) (dev mode, no bundle)"
	@echo ""
	@echo "  make wipe-tcc    Quit app and reset Accessibility grant for $(BUNDLE_ID)"
	@echo "  make wipe-config Quit app and clear stored UserDefaults (hotkeys, prefs)"
	@echo "  make probe-mc    Open MC and dump CGWindowList frames to compare positions"
	@echo "  make clean       Remove .build and generated icon"

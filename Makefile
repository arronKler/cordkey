PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin
APPDIR ?= /Applications
BIN := bin/cordkey
APP := build/CordKey.app
ICONSET := build/AppIcon.iconset
SOURCES := $(wildcard Sources/cordkey/*.swift)
PLIST := $(HOME)/Library/LaunchAgents/io.github.cordkey.cli.plist
LOG := $(HOME)/Library/Logs/cordkey.log
ARGS ?= --play f13

.PHONY: build app app-install app-open install uninstall run watch devices clean service-install service-uninstall service-status

build: $(BIN)

$(BIN): $(SOURCES)
	@mkdir -p bin
	swiftc -O -whole-module-optimization $(SOURCES) \
		-framework IOKit -framework AppKit -framework ApplicationServices \
		-framework CoreAudio -framework SwiftUI \
		-o "$(BIN)"
	@codesign -s - -f --identifier io.github.cordkey.cli "$(BIN)"
	@echo "Built $(BIN)"

app: $(BIN)
	@rm -rf "$(APP)" "$(ICONSET)"
	@mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	@cp "$(BIN)" "$(APP)/Contents/MacOS/CordKey"
	@"./$(BIN)" --write-iconset "$(ICONSET)" && iconutil -c icns "$(ICONSET)" -o "$(APP)/Contents/Resources/AppIcon.icns" && rm -rf "$(ICONSET)"
	@printf '%s\n' \
		'<?xml version="1.0" encoding="UTF-8"?>' \
		'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
		'<plist version="1.0">' \
		'<dict>' \
		'  <key>CFBundleName</key><string>CordKey</string>' \
		'  <key>CFBundleDisplayName</key><string>CordKey</string>' \
		'  <key>CFBundleIdentifier</key><string>io.github.cordkey.app</string>' \
		'  <key>CFBundleVersion</key><string>1.0</string>' \
		'  <key>CFBundleShortVersionString</key><string>1.0</string>' \
		'  <key>CFBundleExecutable</key><string>CordKey</string>' \
		'  <key>CFBundleIconFile</key><string>AppIcon</string>' \
		'  <key>CFBundlePackageType</key><string>APPL</string>' \
		'  <key>LSMinimumSystemVersion</key><string>13.0</string>' \
		'  <key>LSUIElement</key><true/>' \
		'  <key>NSHighResolutionCapable</key><true/>' \
		'</dict>' \
		'</plist>' > "$(APP)/Contents/Info.plist"
	@codesign --deep -s - -f --identifier io.github.cordkey.app "$(APP)"
	@echo "Built $(APP)"

app-install: app
	@rm -rf "$(APPDIR)/CordKey.app"
	@cp -R "$(APP)" "$(APPDIR)/CordKey.app"
	@echo "Installed $(APPDIR)/CordKey.app"

app-open: app
	open "$(APP)"

install: build
	@mkdir -p "$(BINDIR)"
	@cp -f "$(BIN)" "$(BINDIR)/cordkey"
	@codesign -s - -f --identifier io.github.cordkey.cli "$(BINDIR)/cordkey"
	@echo "Installed $(BINDIR)/cordkey"

uninstall:
	@rm -f "$(BINDIR)/cordkey"
	@echo "Removed $(BINDIR)/cordkey"

run: build
	"./$(BIN)" $(ARGS)

watch: build
	"./$(BIN)" watch

devices: build
	"./$(BIN)" devices

service-install: install
	@mkdir -p "$(HOME)/Library/LaunchAgents" "$(HOME)/Library/Logs"
	@CORDKEY_BINDIR="$(BINDIR)" CORDKEY_LOG="$(LOG)" CORDKEY_ARGS="$(ARGS)" CORDKEY_PLIST="$(PLIST)" \
		python3 -c 'import os, plistlib, shlex; plist = {"Label": "io.github.cordkey.cli", "ProgramArguments": [os.path.join(os.environ["CORDKEY_BINDIR"], "cordkey"), "--no-prompt"] + shlex.split(os.environ.get("CORDKEY_ARGS", "")), "RunAtLoad": True, "KeepAlive": True, "StandardOutPath": os.environ["CORDKEY_LOG"], "StandardErrorPath": os.environ["CORDKEY_LOG"]}; open(os.environ["CORDKEY_PLIST"], "wb").write(plistlib.dumps(plist))'
	@launchctl bootout gui/$$(id -u) "$(PLIST)" 2>/dev/null || true
	@launchctl bootstrap gui/$$(id -u) "$(PLIST)"
	@echo "LaunchAgent installed: $(PLIST)"
	@echo "Log: $(LOG)"
	@echo "NOTE: Grant Accessibility permission to $(BINDIR)/cordkey in System Settings → Privacy & Security → Accessibility."

service-uninstall:
	@launchctl bootout gui/$$(id -u) "$(PLIST)" 2>/dev/null || true
	@rm -f "$(PLIST)"
	@echo "LaunchAgent removed: $(PLIST)"

service-status:
	@launchctl print gui/$$(id -u)/io.github.cordkey.cli 2>/dev/null | head -n 20 || echo "io.github.cordkey.cli is not loaded"
	@test -f "$(LOG)" && echo "--- recent log ---" && tail -n 15 "$(LOG)" || true

clean:
	@rm -rf bin build .build

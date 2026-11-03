APP_BUNDLE := $(HOME)/Applications/PRadar.app

.PHONY: build install uninstall test lint format

build:
	swift build -c release

install: build
	pkill -x PRadar || true
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	cp Support/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	cp .build/release/PRadar "$(APP_BUNDLE)/Contents/MacOS/PRadar"
	codesign --force --sign - "$(APP_BUNDLE)"
	open "$(APP_BUNDLE)"

uninstall:
	pkill -x PRadar || true
	rm -rf "$(APP_BUNDLE)"

test:
	swift test

lint:
	swift format lint --strict -r Sources Tests Package.swift

format:
	swift format -i -r Sources Tests Package.swift

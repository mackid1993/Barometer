LOCAL_SWIFT_64_DEVELOPER_DIR := $(firstword $(wildcard \
	/Applications/Xcode_27.0.app/Contents/Developer \
	/Applications/Xcode_27.0.0.app/Contents/Developer \
	/Applications/Xcode-beta.app/Contents/Developer))
DEVELOPER_DIR ?= $(LOCAL_SWIFT_64_DEVELOPER_DIR)
ifeq ($(strip $(DEVELOPER_DIR)),)
DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer
endif
export DEVELOPER_DIR

.PHONY: build test security-audit app dmg run stop install probe clean

build:
	swift build

test:
	swift test --enable-swift-testing

security-audit:
	./Scripts/audit-c-security.sh

app:
	./Scripts/make-app.sh

dmg: app
	./Scripts/create-dmg.sh

run: install

stop:
	-osascript -e 'quit app id "com.barometer.app"'
	-pkill -f 'Barometer.app/Contents/MacOS/Barometer'
	@for attempt in $$(seq 1 30); do \
		if ! pgrep -f 'Barometer.app/Contents/MacOS/Barometer' >/dev/null; then break; fi; \
		sleep 0.1; \
	done

install: app stop
	ditto dist/Barometer.app /Applications/Barometer.app
	sleep 1
	open /Applications/Barometer.app

probe:
	swift run mbs-probe $(SRC)

clean: stop
	swift package clean
	rm -rf dist

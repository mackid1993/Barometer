.PHONY: build test lint format check app dmg run stop install probe clean

build:
	swift build

test:
	swift test

lint:
	swift format lint --strict --recursive --parallel Package.swift Sources Tests

format:
	swift format --in-place --recursive --parallel Package.swift Sources Tests

check: build test lint

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
	open /Applications/Barometer.app

probe:
	swift run mbs-probe $(ARGS)

clean: stop
	swift package clean
	rm -rf dist

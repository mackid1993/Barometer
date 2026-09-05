.PHONY: build test app dmg run stop install probe clean

build:
	swift build

test:
	swift test --enable-swift-testing -Xswiftc -F \
		-Xswiftc "$${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}/Library/Developer/Frameworks"

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

.PHONY: build test app run stop install probe clean

build:
	swift build

test:
	swift test

app:
	./Scripts/make-app.sh

run: install

stop:
	-osascript -e 'quit app id "com.barometer.app"'
	-pkill -f 'Barometer.app/Contents/MacOS/Barometer'

install: app stop
	ditto dist/Barometer.app /Applications/Barometer.app
	open /Applications/Barometer.app

probe:
	swift run mbs-probe $(SRC)

clean: stop
	swift package clean
	rm -rf dist

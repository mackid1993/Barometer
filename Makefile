.PHONY: build test app run stop install probe clean

build:
	swift build

test:
	swift test

app:
	./Scripts/make-app.sh

run: stop app
	open dist/MenuBarStats.app

stop:
	-osascript -e 'quit app id "net.brustein.MenuBarStats"'
	-pkill -f 'MenuBarStats.app/Contents/MacOS/MenuBarStats'

install: app stop
	ditto dist/MenuBarStats.app /Applications/MenuBarStats.app
	open /Applications/MenuBarStats.app

probe:
	swift run mbs-probe $(SRC)

clean: stop
	swift package clean
	rm -rf dist

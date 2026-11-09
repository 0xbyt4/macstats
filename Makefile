.PHONY: build app run probe install clean

build:
	swift build

app:
	./scripts/bundle.sh

run: app
	open build/MacStats.app

probe:
	swift run statsprobe

install: app
	rm -rf /Applications/MacStats.app
	cp -R build/MacStats.app /Applications/MacStats.app

clean:
	rm -rf .build build

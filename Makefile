SHELL := /bin/bash

.PHONY: build run install logic-test smoke-test publish publish-open

build:
	bash build.sh

run:
	bash build.sh && open Gander.app

install:
	bash build.sh
	rm -rf /Applications/Gander.app
	cp -r Gander.app /Applications/Gander.app
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
		-f /Applications/Gander.app
	@echo "✓ Installed to /Applications/Gander.app"

logic-test:
	bash logic-test.sh

smoke-test:
	bash smoke-test.sh

publish:
	bash publish.sh

publish-open:
	bash publish.sh --open
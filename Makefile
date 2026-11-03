SHELL := /bin/bash

.PHONY: build run install logic-test smoke-test publish publish-open

build:
	bash build.sh

run:
	bash build.sh && open "Ur Browse.app"

install: build
	@echo "✓ Local build: $(CURDIR)/Ur Browse.app"
	@echo '  Run: open "Ur Browse.app"'

logic-test:
	bash logic-test.sh

smoke-test:
	bash smoke-test.sh

publish:
	bash publish.sh

publish-open:
	bash publish.sh --open
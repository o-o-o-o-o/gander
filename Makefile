SHELL := /bin/bash

.PHONY: build run install logic-test smoke-test publish publish-open

build:
	bash build.sh

run:
	bash build.sh && open Gander.app

install: build
	@echo "✓ Local build: $(CURDIR)/Gander.app"
	@echo "  Run: open Gander.app"

logic-test:
	bash logic-test.sh

smoke-test:
	bash smoke-test.sh

publish:
	bash publish.sh

publish-open:
	bash publish.sh --open
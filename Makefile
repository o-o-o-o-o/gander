SHELL := /bin/bash

.PHONY: build logic-test smoke-test publish publish-open

build:
	bash build.sh

logic-test:
	bash logic-test.sh

smoke-test:
	bash smoke-test.sh

publish:
	bash publish.sh

publish-open:
	bash publish.sh --open
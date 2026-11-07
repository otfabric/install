.PHONY: check lint test registry registry-check org-scan all-tools

SHELLCHECK ?= $(shell command -v shellcheck 2>/dev/null || echo "docker run --rm -v $(CURDIR):/src:ro -w /src koalaman/shellcheck:stable")

## check: everything CI runs on Linux and macOS
check: registry-check lint test

## lint: shellcheck the POSIX scripts
lint:
	$(SHELLCHECK) -s sh install.sh tests/run.sh tests/all_tools.sh

## test: end-to-end tests of install.sh against the fake release server
test:
	sh tests/run.sh sh

## registry: rewrite the registry blocks and README table from tools.json
registry:
	python3 -I scripts/registry.py

registry-check:
	python3 -I scripts/registry.py --check

## org-scan: find released binaries tools.json does not know (needs gh)
org-scan:
	python3 -I scripts/org_scan.py

## all-tools: install every tool through get.otfabric.io into a temp dir and run it
all-tools:
	sh tests/all_tools.sh all-tools.txt

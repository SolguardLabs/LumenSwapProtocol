.PHONY: all format build test scan verify release-check

all: verify

format:
	forge fmt --check

build:
	forge build --no-lint

test:
	forge test

scan:
	node scripts/public-surface.mjs

verify: format build test scan

release-check:
	node scripts/release-integrity.mjs

# Check, test and run commands for this host-scripted Loup project.
#
# The program is a script (bin/httpd.lpscr) run from source; a script entry
# cannot be compiled (E-BUILD-COMPILED), so there is no build target. It
# runs under Stage0 (`loup-bootstrap run`): on Linux x86-64 the self-hosted
# `loup run` has no network support, and Stage0 enforces the capability
# grants the server is given (file system and network only). On macOS,
# Windows and Linux arm64 `loup` and `loup-bootstrap` are both Stage0.

APP            ?= httpd
LOUP_BOOTSTRAP ?= loup-bootstrap
RUN            ?= $(LOUP_BOOTSTRAP) run --deny-all --allow-fs --allow-net
SCRIPTS        := $(wildcard bin/*.lpscr)
TESTS          ?= $(wildcard tests/*_test.lpscr)
ARGS           ?=
TEST_ARGS      ?=

.PHONY: all run check test e2e ci clean

all: ci

# Serve a directory, e.g. `make run ARGS="-p 8000 tests/fixtures/site"`.
# Stop it with Ctrl-C.
run:
	$(RUN) bin/$(APP).lpscr -- $(ARGS)

# Type-check each entry script and every lib/ module it imports.
check:
	@for script in $(SCRIPTS); do \
		echo "check $$script"; \
		$(LOUP_BOOTSTRAP) check --no-color $$script || exit 1; \
	done

# Unit tests (tests/*_test.lpscr), one file at a time: run all at once, the
# 1.26.0 runner fails random tests with an empty RuntimeError on a busy
# machine. They call the handler directly; no socket is opened.
# Narrow the run: `make test TESTS=tests/handler_test.lpscr TEST_ARGS="--filter etag"`.
test:
	@status=0; for t in $(TESTS); do \
		$(LOUP_BOOTSTRAP) test --no-color --file $$t $(TEST_ARGS) || status=1; \
	done; exit $$status

# End-to-end tests: start the server on a free port over a copy of
# tests/fixtures/site and check its answers with curl.
e2e:
	bash tests/e2e.sh $(LOUP_BOOTSTRAP)

# Everything CI runs, ending with a smoke test of the entry script.
ci: check test e2e
	$(RUN) bin/$(APP).lpscr -- --version

clean:
	rm -rf .temp

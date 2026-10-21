# AGENTS.md

This repository is `httpd`, a small static file server written in the Loup
programming language on the standard library's `net.http` server, part of
the loup-cmd series of example applications. It is a `host.scripted`
project: the program is the `.lpscr` script in `bin/`, run from source by
`loup-bootstrap run` with the `fs` and `net` capabilities, and it imports
`host.dual` modules from `lib/`. Nothing is compiled.

## Skills

| Skill | Location | Use it when |
|-------|----------|-------------|
| `loup-programmer` | [skills/loup-programmer/SKILL.md](skills/loup-programmer/SKILL.md) | Writing, reviewing, debugging or explaining Loup code: `.lpscr`, `.loup`, `.lphc`, `.lpweb` or `.lpfree` source files, `.lppkg` manifests, `@mode(...)` directives, or the `loup` / `loup-bootstrap` commands. |

Read `skills/loup-programmer/SKILL.md` before writing or changing any Loup code
in this repository. It links to detailed references under
`skills/loup-programmer/references/` for syntax, types and ownership, execution
modes and projects, errors and diagnostics, the standard library, and common
mistakes. Load those only as needed.

## Code layout

```text
.
├── package.lppkg                # manifest: name, version, toolchain, [build] entry (bin/httpd.lpscr), [test] pattern
├── Makefile                     # run, check, test, e2e, ci, clean
├── bin/
│   └── httpd.lpscr              # entry script (host.scripted, executable): options, checks, serve(), access log
├── lib/                         # host.dual modules
│   ├── appinfo.loup             # APP_NAME, APP_VERSION, SERVER, exit statuses
│   ├── args.loup                # struct Options, parse_args(), parse_port(), is_bind_address(), split_option()
│   ├── usage.loup               # usage(), version_line()
│   ├── handler.loup             # handle(root, req), finish(), respond(root, req), error_response()
│   ├── paths.loup               # path_segments(): decode and refuse, fs_path(), display_path()
│   ├── mime.loup                # content_type()
│   ├── listing.loup             # struct Entry, listing_page() (an html template fence), href(), label()
│   ├── etag.loup                # fnv1a(), etag_of(), etag_matches()
│   └── accesslog.loup           # log_line(), clf_time() (core.datetime)
├── tests/
│   ├── *_test.lpscr             # unit tests: func test_*(): void (no sockets)
│   ├── e2e.sh                   # end-to-end: server on a free port, curl, access log
│   ├── netcheck.lpscr           # e2e helper (net.tcp): free-port, wait PORT [PATH]
│   └── fixtures/site/           # the site the tests serve (a binary PNG, a dotfile, nested dirs)
├── specs/httpd/                 # requirements.md, design.md, tasks.md
├── skills/loup-programmer/      # the Loup skill and its references
└── .github/workflows/ci.yml     # installs Loup and runs `make ci`
```

## Check, run and test

Prerequisites: Loup 1.26.0 (`loup-bootstrap` on `PATH`), `make`, `bash` and
`curl`.

Loup Lite comes from <https://github.com/code-craft-ai-company/loup-releases>;
[README.md](README.md#installing-loup-lite) has the install commands.

| Task | Command | Notes |
|------|---------|-------|
| Serve a directory | `make run ARGS="-p 8000 tests/fixtures/site"` | `loup-bootstrap run --deny-all --allow-fs --allow-net bin/httpd.lpscr -- ARGS` |
| Run directly | `./bin/httpd.lpscr -p 8000 DIR` | the shebang grants the capabilities |
| Type-check | `make check` | `loup-bootstrap check FILE` for each `bin/*.lpscr` and its imports, and `tests/netcheck.lpscr` |
| Unit tests | `make test` | each `tests/*_test.lpscr` in turn, `--no-parallel` |
| One test file | `make test TESTS=tests/handler_test.lpscr` | |
| Matching tests | `make test TEST_ARGS="--filter etag"` | |
| End-to-end tests | `make e2e` | `tests/e2e.sh`: starts the server, always kills it |
| Everything CI runs | `make ci` | check, test, e2e, then `--version` |
| Clean | `make clean` | removes `.temp/` |

Run `make ci` before reporting a change as done.

Toolchain facts this project depends on (Loup 1.26.0, Linux x86-64):

- The server needs Stage0 (`loup-bootstrap run`). The self-hosted `loup run`
  has no network support (`unsupported method 'net'`). Stage0 grants `net`
  only with `--allow-net`.
- A script entry cannot be built (`E-BUILD-COMPILED`); there is no build
  target. `loup-bootstrap check FILE` type-checks the script and its imports.
- `Response.body` is a string, written as UTF-8 by `serializeResponse`, which
  also writes `Content-Length` itself (a handler's own is dropped). Binary
  files therefore get `501`, and `HEAD` answers carry `Content-Length: 0`.
- `bytes.decode()` turns invalid UTF-8 into U+FFFD; `is_text()` relies on
  that.
- `loup-bootstrap test` with all files at once fails random tests with an
  empty `RuntimeError` on a busy machine, and `--file` alone still runs a
  file's tests in parallel; the Makefile runs one file at a time with
  `--no-parallel`.
- `lib/handler.loup`, `lib/args.loup` and `lib/listing.loup` use features
  only Stage0 runs in 1.26.0 (`in`/`not in`, escapes in `i"..."`, template
  fences with filters); `lib/etag.loup` uses `@overflowWrapping`, which the
  self-hosted `loup run` ignores. Keep them on Stage0.
- `net.http` answers an unparsable request line (or an empty connection) as
  `GET / HTTP/1.1`; `parseRequest` also upper-cases the method.

## Making a change

1. Update the spec in `specs/httpd/` (see [specs/README.md](specs/README.md)).
2. Change the code: request handling in `lib/`, start-up and logging in
   `bin/httpd.lpscr`.
3. Add or update unit tests in `tests/` (call `handle` or `respond` with
   `parseRequest(...)`) and cases in `tests/e2e.sh`.
4. Run `make ci`.
5. Tick the finished tasks in `specs/httpd/tasks.md`.

Keep the handler a function from `Request` to `Response` with no other side
effects than reading files; only `bin/httpd.lpscr` prints and listens.

## Conventions

- `bin/httpd.lpscr` is `@mode(host.scripted)` with the shebang
  `#!/usr/bin/env -S loup-bootstrap run --deny-all --allow-fs --allow-net`
  and the executable bit. Grant no more capabilities than it uses.
- `lib/*.loup` are `@mode(host.dual)`: declarations only, no `Any`.
- Imports are relative: `from ..lib.handler import (...)` in `bin/` and
  `tests/`, `from .paths import (...)` inside `lib/`.
- Fields of a `Response` are changed inside `safe { ... }`.
- Tests read fixtures by paths relative to the repository root
  (`tests/fixtures/site`); run them from there (`make test` does).
- Keep `APP_VERSION` in `lib/appinfo.loup`, `SERVER` and `version` in
  `package.lppkg` in step.
- The skill documents toolchain 1.25.1; this project targets 1.26.0. When
  they disagree, trust the toolchain's behaviour.

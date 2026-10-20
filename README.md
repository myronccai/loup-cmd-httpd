# loup-cmd-httpd

A small static file server written as a [Loup](https://code-craft.ai/references/loup)
script on the standard library's `net.http` server: MIME types,
`index.html`, generated directory listings, `304`/`404`/`405`,
path-traversal protection and an access log.

Part of the **loup-cmd** series of example applications: classic Linux and
Windows commands, and projects for each Loup execution mode, each in its own
repository under [myronccai](https://github.com/myronccai?tab=repositories&q=loup-cmd).
This one is a `host.scripted` project: a thin `.lpscr` entry script in `bin/`
over `host.dual` modules in `lib/`, run from source with the network
capability granted.

## Requirements

- Loup 1.26.0 or later (`loup-bootstrap` on `PATH`):

  ```sh
  curl -fsSL https://github.com/code-craft-ai-company/loup-releases/releases/latest/download/loup-install.sh | sh
  ```

- `make`, `bash`, `curl` and `python3` for the tests. Nothing is built.

## Usage

```sh
./bin/httpd.lpscr -p 8000 site/                                    # the shebang grants fs and net
loup-bootstrap run --allow-net bin/httpd.lpscr -- -p 8000 site/   # the same, by hand
make run ARGS="-p 8000 tests/fixtures/site"
make ci                                                           # check, unit tests, end-to-end tests
```

**Which runner.** The server runs under Stage0, `loup-bootstrap run`. On
Linux x86-64 `loup run` is the self-hosted driver, which has no network
support in 1.26.0 (`loup: interpreter v1: unsupported method 'net'`); on
macOS, Windows and Linux arm64 `loup` is Stage0 too, so
`loup run --allow-net bin/httpd.lpscr -- ...` works there.

**Capabilities.** Stage0 grants a script file-system, process and entropy
access by default, and network access only on request. The shebang line,
`#!/usr/bin/env -S loup-bootstrap run --deny-all --allow-fs --allow-net`,
grants exactly what the server uses. Without `--allow-net`:

```text
$ loup-bootstrap run --deny-all --allow-fs bin/httpd.lpscr -- -p 8765 tests/fixtures/site; echo "status $?"
httpd: serving tests/fixtures/site on http://127.0.0.1:8765/
httpd: cannot listen on 127.0.0.1:8765: capability 'net' is not available: not in permission set
status 1
```

A session with `./bin/httpd.lpscr -p 8765 tests/fixtures/site` running:

```text
$ curl -i http://127.0.0.1:8765/docs/
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
Server: loup-cmd-httpd/0.1.0
Content-Length: 339
Connection: close

<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>Index of /docs/</title></head>
<body>
<h1>Index of /docs/</h1>
<ul>
<li><a href="../">../</a></li>
<li><a href="sub/">sub/</a></li>
<li><a href="a%20b.txt">a b.txt</a></li>
<li><a href="guide.md">guide.md</a></li>
<li><a href="x%26y.txt">x&amp;y.txt</a></li>
</ul>
</body>
</html>
$ curl -sI http://127.0.0.1:8765/style.css
HTTP/1.1 200 OK
Content-Type: text/css; charset=utf-8
ETag: "22-3cd12149"
Server: loup-cmd-httpd/0.1.0
Content-Length: 0
Connection: close

$ curl -s -o /dev/null -w "%{http_code}\n" -H 'If-None-Match: "22-3cd12149"' http://127.0.0.1:8765/style.css
304
$ curl -s --path-as-is http://127.0.0.1:8765/../package.lppkg
403 Forbidden
$ curl -s -X DELETE http://127.0.0.1:8765/notes.txt
405 Method Not Allowed
$ curl -s http://127.0.0.1:8765/pixel.png
501 Not Implemented
```

The server's standard error and standard output (the access log):

```text
httpd: serving tests/fixtures/site on http://127.0.0.1:8765/
- - - [20/Oct/2026:07:31:18 +0000] "GET /docs/ HTTP/1.1" 200 339 "-" "curl/8.14.1"
- - - [20/Oct/2026:07:31:18 +0000] "HEAD /style.css HTTP/1.1" 200 - "-" "curl/8.14.1"
- - - [20/Oct/2026:07:31:18 +0000] "GET /style.css HTTP/1.1" 304 - "-" "curl/8.14.1"
- - - [20/Oct/2026:07:31:18 +0000] "GET /../package.lppkg HTTP/1.1" 403 14 "-" "curl/8.14.1"
- - - [20/Oct/2026:07:31:18 +0000] "DELETE /notes.txt HTTP/1.1" 405 23 "-" "curl/8.14.1"
- - - [20/Oct/2026:07:31:18 +0000] "GET /pixel.png HTTP/1.1" 501 20 "-" "curl/8.14.1"
```

The log is in Combined Log Format, so
[loup-cmd-logwatch](https://github.com/myronccai/loup-cmd-logwatch) reads it:
`./bin/httpd.lpscr site/ > access.log`, then
`./bin/logwatch.lpscr -r status access.log` in that repository.

### Options

| Option | Meaning |
|---|---|
| `-p`, `--port PORT` | port to listen on (default 8080) |
| `-b`, `--bind ADDRESS` | address to listen on (default `127.0.0.1`; `0.0.0.0` for every interface) |
| `-q`, `--quiet` | no access log |
| `-h`, `--help` / `-V`, `--version` | help text / `httpd (loup-cmd-httpd) 0.1.0` |

`DIR` defaults to the current directory. Under `loup-bootstrap run`, options
go after `--` (Stage0 rejects unknown `--` flags before it); the shebang
form takes them directly only if they are short (`-p 8000`), so write
`./bin/httpd.lpscr -- --port 8000` for long ones.

### Behaviour

| Request | Answer |
|---|---|
| `GET` a file | `200`, `Content-Type` by extension, `ETag` (length and FNV-1a hash of the content) |
| `GET` a directory, path ends in `/` | its `index.html`, or a generated listing (directories first, hidden entries left out) |
| `GET` a directory without the `/` | `301` to the path with `/` (query kept) |
| `If-None-Match` with the current `ETag` (or `*`) | `304`, no body |
| `HEAD` | as `GET`, without the body |
| a `..` segment, also as `%2e%2e` | `403` |
| a segment starting with `.` | `404` |
| bad `%` escape, NUL or backslash in the path | `400` |
| any other method | `405` with `Allow: GET, HEAD` |
| nothing at the path | `404` |
| a file that is not UTF-8 text (an image) | `501` |
| the handler fails | `500`, and the server keeps running |

Exit status: `1` if DIR is not a directory or the server cannot listen, `2`
for a usage error. Otherwise it serves until stopped (Ctrl-C).

## What this example shows

- **`net.http` with the handler as a plain function.** `serve(host, port,
  handler)` takes a `fn(Request): Response`. `lib/handler.loup` holds that
  function, so the unit tests build requests with
  `parseRequest("GET /docs HTTP/1.1\r\n\r\n")` and check the `Response`
  without a socket. The script's closure only adds the access log.
- **Capability grants.** The script asks for `fs` and `net` and nothing else
  (`--deny-all --allow-fs --allow-net`), and a missing grant is an ordinary
  `IoError` the script reports.
- **A thin script over dual-mode modules**, as in
  [loup-cmd-logwatch](https://github.com/myronccai/loup-cmd-logwatch):
  `bin/httpd.lpscr` does options, checks and `serve`; `lib/*.loup` does the
  rest, imported with relative paths (`from ..lib.handler import (respond);`).
- **Safe path mapping.** The path is percent-decoded first (`data.query`)
  and split into segments; `..`, hidden segments, NUL and backslash are
  refused before the file system is touched.
- **Working within the toolchain.** No `stat()` in `io.fs` means no
  `Last-Modified`, so `304` comes from a content hash; the access log's UTC
  time is computed from `system.time.realtimeNs()` with integer date
  arithmetic.

## Limitations (Loup 1.26.0)

- **Binary files get `501`.** `net.http` writes a response body as a UTF-8
  string and `bytes.decode()` replaces invalid bytes, so an image cannot be
  sent unchanged through `serve`. Text formats (HTML, CSS, JavaScript, JSON,
  SVG, Markdown, plain text) are served.
- **`HEAD` responses say `Content-Length: 0`**: `net.http` computes the
  length from the (empty) body and drops a handler's own `Content-Length`.
- One connection at a time, one read of up to 64 KiB per request,
  `Connection: close` (the `net.http` MVP). No ranges, compression or TLS.
- The access log's client address is `-`: the handler is not given it.
- No `Last-Modified`/`If-Modified-Since` (no `stat()`), and symbolic links
  are followed (they cannot be told apart from their targets).

## Layout

```text
bin/httpd.lpscr             # the server (host.scripted entry script)
lib/appinfo.loup            # name, version, Server header, exit statuses
lib/args.loup               # option parsing
lib/usage.loup              # --help and --version text
lib/handler.loup            # handle(root, req) and respond(): the request handler
lib/paths.loup              # decoding and checking request paths
lib/mime.loup               # content types by extension
lib/listing.loup            # directory listing page
lib/etag.loup               # FNV-1a entity tags, If-None-Match
lib/accesslog.loup          # Combined Log Format lines, UTC dates
tests/*_test.lpscr          # unit tests, no sockets (make test)
tests/e2e.sh                # server on a free port, checked with curl (make e2e)
tests/fixtures/site/        # the site the tests serve
specs/httpd/                # requirements, design, tasks
```

[AGENTS.md](AGENTS.md) has every check and test command and the conventions
for changing the code.

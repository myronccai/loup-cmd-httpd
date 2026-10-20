# Design: httpd

## Overview

`bin/httpd.lpscr` is a `host.scripted` script run by Stage0 with the `fs`
and `net` capabilities. Its top-level statements parse `args()` into
`Options`, handle `--help` and `--version`, check that DIR is a directory,
print the banner, and call `net.http.serve` with a closure. The closure
passes each `Request` to `respond(root, req)` from `lib/handler.loup` and,
unless `--quiet`, prints `log_line(...)`. `serve` never returns; an
`IoError` from it (address in use, `net` not granted) is reported with
status 1.

```text
serve ─► closure(req) ─► respond(root, req) ─► handle(root, req) ─► Response
                    └──► println(log_line(req, resp, now))
```

## Modules

| Module | Contents |
|---|---|
| `bin/httpd.lpscr` | top level: options, directory check, banner, `serve` with the logging closure |
| `lib/appinfo.loup` | name, version, `SERVER`, exit statuses |
| `lib/args.loup` | `Options`, `parse_args` (short clusters, attached values, `--name=value`), `parse_port` |
| `lib/usage.loup` | `usage()`, `version_line()` |
| `lib/handler.loup` | `handle`, `finish`, `respond`, `error_response`, `content_response`, `is_text` |
| `lib/paths.loup` | `path_segments`, `fs_path`, `display_path` |
| `lib/mime.loup` | `content_type` from a table keyed by lower-cased extension |
| `lib/listing.loup` | `Entry`, `sorted_entries`, `listing_page`, `html_escape` |
| `lib/etag.loup` | `fnv1a`, `etag_of`, `etag_matches` |
| `lib/accesslog.loup` | `civil_from_days`, `clf_time`, `log_line` |

### Handling a request

1. Methods other than `GET` and `HEAD`: `405` with `Allow: GET, HEAD`.
2. `path_segments(req.path)`: `percentDecode` (non-form, so `+` stays `+`;
   a bad escape throws and becomes `400`), then `400` for a NUL or a
   backslash, then split on `/`, dropping empty and `.` segments; `..` is
   `403` and a segment starting with `.` is `404`. Nothing is resolved
   against the file system before this succeeds, so encoded forms such as
   `%2e%2e%2f` are refused like plain ones.
3. A directory: without a trailing `/` in the request path, `301` to the
   path plus `/` (and `?query`); else its `index.html`, else a listing from
   `listDir` (dot entries dropped, directories first, names escaped for HTML
   and percent-encoded for links).
4. A file: `readBytes`, then `content_response`: `decode()`; if the text is
   not the same bytes (`is_text`), `501`; the ETag is
   `"<length hex>-<FNV-1a hex>"`; a matching `If-None-Match` gives `304`
   with the ETag and no body; else `200` with `content_type(name)`.
5. Anything else: `404`. A read failure is `403`.

`respond` is `finish(req, handle)`: an exception becomes `500`, every response gets
`Server: loup-cmd-httpd/0.1.0`, and a `HEAD` response's body is emptied
(inside `safe { }`, as `body` is a class field).

### Access log

`log_line(req, resp, epoch_seconds)` writes Combined Log Format with host,
ident and user `-` (the handler does not see the client address), the time
from `clf_time` (UTC; `civil_from_days` is the inverse of the usual
days-from-civil algorithm, integers only), the request line as received,
the status, the body's byte length (`-` for zero), and the Referer and
User-Agent headers quoted with `"` and `\` escaped.

## What this example shows

- `net.http.serve` with the handler as a plain function, tested through
  `parseRequest` with no socket.
- Capability grants: `--deny-all --allow-fs --allow-net` in the shebang, and
  the failure without `--allow-net`.
- A thin script over `host.dual` modules with relative imports.
- Content-hash ETags where `io.fs` has no `stat()`.

## Deviations forced by the toolchain

- The self-hosted `loup run` cannot run `serve`, so the script runs under
  `loup-bootstrap run` (Stage0) on Linux x86-64.
- Binary files: `501` (string bodies). `HEAD`: `Content-Length: 0`.
- No `Last-Modified` (no `stat()`); no client address in the log.

## Error handling

- Usage errors: message and `Try 'httpd --help' ...` on standard error,
  status 2. DIR not a directory: `httpd: DIR: not a directory`, status 1.
- `serve` failing: `httpd: cannot listen on ADDRESS:PORT: REASON`, status 1.
- Per request: every failure is an HTTP status; the server keeps serving.

## Testing

- `tests/paths_test.lpscr`: decoding, empty and `.` segments, every refusal
  (plain and encoded `..`, hidden, bad escape, NUL, backslash).
- `tests/handler_test.lpscr`: index, types, query ignored, redirect with
  query, listings, `304`, every refusal, `405`, `respond`'s Server header
  and `HEAD`, `is_text`.
- `tests/listing_test.lpscr`, `tests/mime_test.lpscr`,
  `tests/etag_test.lpscr` (FNV-1a checked against an independent
  implementation), `tests/accesslog_test.lpscr` (dates, escaping, dashes),
  `tests/args_test.lpscr`.
- `tests/e2e.sh`: command-line errors and the missing `net` grant; then a
  server on a free port over a copy of the fixture site in `$TMP`, checked
  with `curl --path-as-is` (200, 301, 304, 400, 403, 404, 405, 501, HEAD,
  listing body, headers), a second server on the same port, and the access
  log compared line by line with the timestamps masked. A trap kills the
  server on every exit path.

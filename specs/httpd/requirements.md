# Requirements: httpd

## Introduction

`httpd` serves the files under a directory over HTTP/1.1: a small static
file server for local development and for showing how a Loup script uses
the standard library's `net.http` server and the capability grants of
`loup run`. It answers `GET` and `HEAD`, picks a MIME type from the file
extension, serves `index.html` for a directory or generates a listing,
answers conditional requests with `304`, refuses paths that leave the
served directory, and writes an access log that `loup-cmd-logwatch` can
read.

It is the second host-scripted project of the loup-cmd series: a thin
`host.scripted` entry script in `bin/` over `host.dual` modules in `lib/`.
The request handler is a plain function from `Request` to `Response`, so it
is tested without a socket.

## Requirements

### Requirement 1: Serving

**User Story:** As a developer, I want to serve a directory over HTTP so that
I can open its pages in a browser.

#### Acceptance Criteria

1. WHEN httpd is started with a directory (default `.`), THE program SHALL
   listen on `-b ADDRESS` (default `127.0.0.1`) and `-p PORT` (default 8080)
   and print `httpd: serving DIR on http://ADDRESS:PORT/` on standard error.
2. WHEN a `GET` request names a file under the directory, THE handler SHALL
   answer `200` with the file's content, a `Content-Type` chosen from its
   extension (`text/html; charset=utf-8` for `.html`, ... and
   `application/octet-stream` for an unknown extension) and an `ETag`.
3. WHEN the request names a directory, THE handler SHALL answer with its
   `index.html` if there is one, or else with a generated HTML listing of its
   entries (directories first, each group by name, hidden entries left out,
   names HTML-escaped and links percent-encoded, a `../` link below the
   root).
4. WHEN the request names a directory without a trailing `/`, THE handler
   SHALL answer `301` with `Location` set to the path with a `/` added (and
   the query kept).
5. WHEN the request is `HEAD`, THE handler SHALL answer as for `GET` without
   a body.
6. WHEN a request carries `If-None-Match` with the file's current `ETag`
   (or `*`), THE handler SHALL answer `304` with the `ETag` and no body.
7. THE handler SHALL percent-decode the request path, and ignore the query
   string when it maps the path to a file.

### Requirement 2: Refusals and errors

**User Story:** As the person running the server, I want it to serve only
the directory I chose so that nothing else on my machine is exposed.

#### Acceptance Criteria

1. WHEN a decoded path segment is `..`, THE handler SHALL answer `403`
   without touching the file system.
2. WHEN a path segment starts with `.` (a hidden file or directory, such as
   `.git`), THE handler SHALL answer `404`.
3. WHEN the path has a malformed percent escape, a NUL or a backslash, THE
   handler SHALL answer `400`.
4. WHEN the method is not `GET` or `HEAD`, THE handler SHALL answer `405`
   with `Allow: GET, HEAD`.
5. WHEN nothing exists at the path, THE handler SHALL answer `404`.
6. WHEN a file is not valid UTF-8 text, THE handler SHALL answer `501`
   (`net.http` sends bodies as UTF-8 strings, so binary files cannot be sent
   unchanged).
7. WHEN a file cannot be read, THE handler SHALL answer `403`; WHEN the
   handler fails unexpectedly, THE server SHALL answer `500` and keep
   running.
8. THE error responses SHALL have a `text/plain; charset=utf-8` body of the
   form `404 Not Found`, and every response SHALL carry
   `Server: loup-cmd-httpd/0.1.0`.

### Requirement 3: Access log

**User Story:** As an operator, I want an access log so that I can see and
analyse what was requested.

#### Acceptance Criteria

1. WHEN a request has been answered, THE program SHALL write one line in
   Combined Log Format to standard output:
   `- - - [DD/Mon/YYYY:HH:MM:SS +0000] "METHOD TARGET VERSION" STATUS BYTES
   "REFERER" "USER-AGENT"`, in UTC, with `-` for an unknown client address,
   zero bytes and absent headers, and `"` and `\` escaped.
2. WHEN `-q`/`--quiet` is given, THE program SHALL write no access log.

### Requirement 4: Command line and capabilities

**User Story:** As a user, I want conventional options and a clear failure
when the server cannot run so that I can script it.

#### Acceptance Criteria

1. THE program SHALL accept `-p/--port PORT`, `-b/--bind ADDRESS`,
   `-q/--quiet`, `-h/--help` and `-V/--version`, with values attached or
   separate (`-p8000`, `-p 8000`, `--port=8000`), and at most one DIR.
2. WHEN an option is unknown or invalid (a port outside 1 to 65535, a second
   DIR), THE program SHALL print `httpd: MESSAGE` and
   `Try 'httpd --help' for more information.` on standard error and exit with
   status 2.
3. WHEN DIR is not a directory, THE program SHALL print
   `httpd: DIR: not a directory` and exit with status 1.
4. WHEN the server cannot listen (the address is in use, or the `net`
   capability was not granted), THE program SHALL print
   `httpd: cannot listen on ADDRESS:PORT: REASON` and exit with status 1.
5. THE entry script SHALL run under `loup-bootstrap run --deny-all --allow-fs
   --allow-net` (its shebang line): file-system and network access only.
6. WHEN `--version` is given, THE program SHALL print
   `httpd (loup-cmd-httpd) 0.1.0`.

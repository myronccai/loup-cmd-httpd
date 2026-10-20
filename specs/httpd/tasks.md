# Tasks: httpd

- [x] 1. Layout: `bin/httpd.lpscr` over `lib/` modules, Stage0 runner with `--deny-all --allow-fs --allow-net`
  - _Requirements: 4.5_
- [x] 2. Decode and check request paths (`..`, hidden, NUL, backslash, bad escapes)
  - _Requirements: 1.7, 2.1, 2.2, 2.3_
- [x] 3. Serve files with content types and ETags; `304` on a matching If-None-Match
  - _Requirements: 1.2, 1.6_
- [x] 4. Directories: redirect, `index.html`, generated listing
  - _Requirements: 1.3, 1.4_
- [x] 5. Methods: `HEAD` without a body, `405` with `Allow`
  - _Requirements: 1.5, 2.4_
- [x] 6. Errors: `404`, `501` for binary files, `403` for unreadable ones, `500` and keep serving, Server header
  - _Requirements: 2.5, 2.6, 2.7, 2.8_
- [x] 7. Access log in Combined Log Format, `--quiet`
  - _Requirements: 3.1, 3.2_
- [x] 8. Options, banner, usage errors, directory check, listen failures, version
  - _Requirements: 1.1, 4.1, 4.2, 4.3, 4.4, 4.6_
- [x] 9. Unit tests through `parseRequest`; end-to-end tests with a background server and curl
  - _Requirements: all_

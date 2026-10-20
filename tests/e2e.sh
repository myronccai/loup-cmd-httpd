#!/usr/bin/env bash
# End-to-end tests: start the server in the background on a free port over a
# copy of tests/fixtures/site in a temporary directory, check its answers
# with curl, compare the access log, and always stop the server.
#
# usage: tests/e2e.sh [LOUP_BOOTSTRAP]     (run from the repository root)

set -u
LOUP=${1:-loup-bootstrap}
GRANTS=(run --deny-all --allow-fs --allow-net)
SCRIPT=bin/httpd.lpscr
TMP=$(mktemp -d)
SERVER_PID=""
pass=0
fail=0

stop_server() {
    if [ -n "$SERVER_PID" ]; then
        kill "$SERVER_PID" 2> /dev/null
        wait "$SERVER_PID" 2> /dev/null
        SERVER_PID=""
    fi
}
trap 'stop_server; rm -rf "$TMP"' EXIT
trap 'exit 130' INT TERM

free_port() {
    python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

# same NAME EXPECTED ACTUAL
same() {
    if [ "$2" == "$3" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL: $1"
        diff <(printf '%s\n' "$2") <(printf '%s\n' "$3") | sed 's/^/    /' | head -20
    fi
}

# --- command line (no server) -------------------------------------------------

# cli NAME STATUS EXPECTED_STDOUT EXPECTED_STDERR [ARGS...]
cli() {
    local name=$1 want_status=$2 want_out=$3 want_err=$4
    shift 4
    "$LOUP" "${GRANTS[@]}" "$SCRIPT" -- "$@" < /dev/null > "$TMP/out" 2> "$TMP/err"
    local status=$?
    same "$name: status" "$want_status" "$status"
    same "$name: stdout" "$want_out" "$(cat "$TMP/out")"
    same "$name: stderr" "$want_err" "$(cat "$TMP/err")"
}

HINT="Try 'httpd --help' for more information."
cli "version"        0 "httpd (loup-cmd-httpd) 0.1.0" "" --version
cli "bad port"       2 "" "httpd: invalid port '70000'
$HINT" -p 70000
cli "unknown option" 2 "" "httpd: unrecognized option '--bogus'
$HINT" --bogus
cli "two dirs"       2 "" "httpd: extra operand 'b'
$HINT" a b
cli "not a directory" 1 "" "httpd: tests/e2e.sh: not a directory" tests/e2e.sh
"$LOUP" "${GRANTS[@]}" "$SCRIPT" -- --help > "$TMP/out" 2>&1
same "help" "usage: httpd [OPTION]... [DIR]" "$(head -1 "$TMP/out")"

# Without the net capability the listener cannot be opened.
PORT=$(free_port)
"$LOUP" run --deny-all --allow-fs "$SCRIPT" -- -p "$PORT" tests/fixtures/site > "$TMP/out" 2> "$TMP/err"
same "no net capability: status" 1 $?
same "no net capability: stderr" "httpd: serving tests/fixtures/site on http://127.0.0.1:$PORT/
httpd: cannot listen on 127.0.0.1:$PORT: capability 'net' is not available: not in permission set" "$(cat "$TMP/err")"

# --- the server -----------------------------------------------------------------

cp -r tests/fixtures/site "$TMP/site"
printf 'SECRET outside the site\n' > "$TMP/outside.txt"
PORT=$(free_port)
URL="http://127.0.0.1:$PORT"
"$LOUP" "${GRANTS[@]}" "$SCRIPT" -- -p "$PORT" "$TMP/site" > "$TMP/access.log" 2> "$TMP/server.err" &
SERVER_PID=$!

ready=no
for _ in $(seq 1 100); do
    if curl -s -o /dev/null -A probe "$URL/"; then
        ready=yes
        break
    fi
    kill -0 "$SERVER_PID" 2> /dev/null || break
    sleep 0.2
done
same "server started" yes "$ready"
same "banner" "httpd: serving $TMP/site on $URL/" "$(cat "$TMP/server.err")"
if [ "$ready" != yes ]; then
    echo "e2e: $pass passed, $((fail + 1)) failed (server did not start)"
    exit 1
fi

# fetch PATH [CURL ARGS...]: prints the status code; headers in $TMP/headers,
# body in $TMP/body. The path is sent as is (no client-side `..` removal).
fetch() {
    local path=$1
    shift
    rm -f "$TMP/headers" "$TMP/body"
    touch "$TMP/body"
    curl -s --path-as-is -A e2e -D "$TMP/headers" -o "$TMP/body" -w '%{http_code}' "$@" "$URL$path"
}

# header NAME: the value of a response header from the last fetch.
header() {
    grep -i "^$1:" "$TMP/headers" | head -1 | cut -d' ' -f2- | tr -d '\r'
}

same "GET /"                 200 "$(fetch /)"
same "GET / body"            "$(cat "$TMP/site/index.html")" "$(cat "$TMP/body")"
same "GET / type"            "text/html; charset=utf-8" "$(header Content-Type)"
same "Server header"         "loup-cmd-httpd/0.1.0" "$(header Server)"

same "GET /style.css"        200 "$(fetch /style.css)"
same "css type"              "text/css; charset=utf-8" "$(header Content-Type)"
ETAG=$(header ETag)
same "etag"                  '"22-3cd12149"' "$ETAG"
same "If-None-Match"         304 "$(fetch /style.css -H "If-None-Match: $ETAG")"
same "304 has no body"       "" "$(cat "$TMP/body")"
same "stale If-None-Match"   200 "$(fetch /style.css -H 'If-None-Match: "old"')"

same "GET /notes.txt"        200 "$(fetch /notes.txt)"
same "UTF-8 body"            "Café notes: UTF-8 text." "$(cat "$TMP/body")"
same "GET /data.json type"   200 "$(fetch /data.json)"
same "json type"             "application/json" "$(header Content-Type)"
same "encoded name"          200 "$(fetch '/docs/a%20b.txt')"

same "GET /docs"             301 "$(fetch /docs)"
same "redirect location"     "/docs/" "$(header Location)"
same "GET /docs/"            200 "$(fetch /docs/)"
same "directory listing" '<!DOCTYPE html>
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
</html>' "$(cat "$TMP/body")"

same "GET /missing"          404 "$(fetch /missing)"
same "404 body"              "404 Not Found" "$(cat "$TMP/body")"
same "hidden file"           404 "$(fetch /.secret)"
same "traversal"             403 "$(fetch /../outside.txt)"
same "traversal body"        "403 Forbidden" "$(cat "$TMP/body")"
same "encoded traversal"     403 "$(fetch /%2e%2e/outside.txt)"
same "deep traversal"        403 "$(fetch /docs/../../outside.txt)"
same "bad escape"            400 "$(fetch /a%zz)"
same "binary file"           501 "$(fetch /pixel.png)"

same "POST"                  405 "$(fetch / -X POST -d x=1)"
same "Allow header"          "GET, HEAD" "$(header Allow)"
same "HEAD"                  200 "$(fetch / -I)"
same "HEAD headers"          '"dc-df64d14c"' "$(header ETag)"
same "HEAD has no body"      0 "$(header Content-Length)"

# A second server on the same port cannot listen.
"$LOUP" "${GRANTS[@]}" "$SCRIPT" -- -q -p "$PORT" "$TMP/site" > /dev/null 2> "$TMP/err"
same "port in use: status"   1 $?
same "port in use: stderr"   "httpd: cannot listen on 127.0.0.1:$PORT: tcp_bind failed on '127.0.0.1:$PORT': Address already in use (os error 98)" "$(tail -1 "$TMP/err")"

kill -0 "$SERVER_PID" 2> /dev/null
same "server still running"  0 $?

# The access log, with the timestamps replaced (the readiness probes left out).
TIME_RE='\[[0-9]{2}/[A-Z][a-z]{2}/[0-9]{4}:[0-9]{2}:[0-9]{2}:[0-9]{2} \+0000\]'
same "log timestamps" 0 "$(grep -v '"probe"$' "$TMP/access.log" | grep -cvE "^- - - $TIME_RE ")"
same "access log" '- - - [T] "GET / HTTP/1.1" 200 220 "-" "e2e"
- - - [T] "GET /style.css HTTP/1.1" 200 34 "-" "e2e"
- - - [T] "GET /style.css HTTP/1.1" 304 - "-" "e2e"
- - - [T] "GET /style.css HTTP/1.1" 200 34 "-" "e2e"
- - - [T] "GET /notes.txt HTTP/1.1" 200 25 "-" "e2e"
- - - [T] "GET /data.json HTTP/1.1" 200 29 "-" "e2e"
- - - [T] "GET /docs/a%20b.txt HTTP/1.1" 200 19 "-" "e2e"
- - - [T] "GET /docs HTTP/1.1" 301 - "-" "e2e"
- - - [T] "GET /docs/ HTTP/1.1" 200 339 "-" "e2e"
- - - [T] "GET /missing HTTP/1.1" 404 14 "-" "e2e"
- - - [T] "GET /.secret HTTP/1.1" 404 14 "-" "e2e"
- - - [T] "GET /../outside.txt HTTP/1.1" 403 14 "-" "e2e"
- - - [T] "GET /%2e%2e/outside.txt HTTP/1.1" 403 14 "-" "e2e"
- - - [T] "GET /docs/../../outside.txt HTTP/1.1" 403 14 "-" "e2e"
- - - [T] "GET /a%zz HTTP/1.1" 400 16 "-" "e2e"
- - - [T] "GET /pixel.png HTTP/1.1" 501 20 "-" "e2e"
- - - [T] "POST / HTTP/1.1" 405 23 "-" "e2e"
- - - [T] "HEAD / HTTP/1.1" 200 - "-" "e2e"' "$(grep -v '"probe"$' "$TMP/access.log" | sed -E "s#$TIME_RE#[T]#")"

stop_server
echo "e2e: $pass passed, $fail failed"
[ "$fail" -eq 0 ]

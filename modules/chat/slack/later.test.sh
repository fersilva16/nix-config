#!/usr/bin/env bash
# Run by hand: bash later.test.sh
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)/later.sh"
TMP=$(mktemp -d)

cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

export TMUX_SLACK_LATER_CACHE_ROOT="$TMP/cache"
export TMPDIR="$TMP/tmp"
export TMUX_SLACK_LATER_CHROME_VERSION=123.0.0.0
mkdir -p "$TMPDIR" "$TMP/bin"

OPENSSL=${TMUX_SLACK_LATER_OPENSSL:-openssl}
if ! "$OPENSSL" enc -help 2>&1 | grep -q -- '-saltlen'; then
  OPENSSL="$(nix path-info --offline nixpkgs#openssl 2>/dev/null | head -n 1)/bin/openssl"
fi
[[ -x "$OPENSSL" ]] || {
  echo 'FAIL OpenSSL with -saltlen support is required' >&2
  exit 1
}
export PATH="$TMP/bin:${OPENSSL%/*}:$PATH"

namespace() {
  printf '%s\0%s' "$TMUX_SLACK_LATER_PROFILE" "$TMUX_SLACK_LATER_WORKSPACE" \
    | sha256sum | awk '{ print $1 }'
}

cache() {
  printf '%s/%s.json' "$TMUX_SLACK_LATER_CACHE_ROOT" "$(namespace)"
}

check() {
  local label=$1 expected=$2 actual=$3
  if [[ "$actual" == "$expected" ]]; then
    printf 'ok   %s\n' "$label"
  else
    printf 'FAIL %s: expected %s, got %s\n' "$label" "$expected" "$actual" >&2
    exit 1
  fi
}

contains() {
  local label=$1 needle=$2 haystack=$3
  if [[ "$haystack" == *"$needle"* ]]; then
    printf 'ok   %s\n' "$label"
  else
    printf 'FAIL %s: expected %s in %s\n' "$label" "$needle" "$haystack" >&2
    exit 1
  fi
}

not_contains() {
  local label=$1 needle=$2 haystack=$3
  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'ok   %s\n' "$label"
  else
    printf 'FAIL %s: did not expect %s in %s\n' "$label" "$needle" "$haystack" >&2
    exit 1
  fi
}

chrome_key() {
  local result
  export CHROME_SAFE_STORAGE_PASSWORD=test
  result=$("$OPENSSL" enc -aes-128-cbc -P -md sha1 -iter 1003 -saltlen 9 \
    -pass env:CHROME_SAFE_STORAGE_PASSWORD \
    -S 73616c747973616c74 2>/dev/null | awk -F= '/^key=/{ print $2 }')
  unset CHROME_SAFE_STORAGE_PASSWORD
  printf '%s' "$result"
}

key=$(chrome_key)
check "Chromium PBKDF2 vector" "63009C1422826BB1E156C7A1A4F5B5A8" "$key"

encrypted_hex() {
  local domain=$1 value=$2 blob="$TMP/cookie.blob"
  {
    printf 'v10'
    {
      printf '%s' "$domain" | "$OPENSSL" dgst -sha256 -binary
      printf '%s' "$value"
    } | "$OPENSSL" enc -aes-128-cbc -K "$key" \
      -iv 20202020202020202020202020202020
  } >"$blob"
  od -An -tx1 -v "$blob" | tr -d ' \n'
}

add_plain_cookie() {
  local db=$1 created=$2 domain=$3 name=$4 value=$5 path=$6 expires=$7 secure=$8
  sqlite3 "$db" "
    insert into cookies
      (creation_utc, host_key, name, value, encrypted_value, path, expires_utc, is_secure)
    values ($created, '$domain', '$name', '$value', X'', '$path', $expires, $secure);
  "
}

add_encrypted_cookie() {
  local db=$1 created=$2 domain=$3 name=$4 value=$5 path=$6 expires=$7 secure=$8 encrypted
  encrypted=$(encrypted_hex "$domain" "$value")
  sqlite3 "$db" "
    insert into cookies
      (creation_utc, host_key, name, value, encrypted_value, path, expires_utc, is_secure)
    values ($created, '$domain', '$name', '', X'$encrypted', '$path', $expires, $secure);
  "
}

create_profile() {
  local profile=$1
  local db="$profile/Cookies"
  mkdir -p "$profile/Local Storage/leveldb"
  sqlite3 "$db" <<'SQL'
create table meta (key longvarchar not null unique primary key, value longvarchar);
insert into meta values ('version', '24');
create table cookies (
  creation_utc integer primary key,
  host_key text not null,
  name text not null,
  value text not null,
  encrypted_value blob not null,
  path text not null,
  expires_utc integer not null,
  is_secure integer not null
);
SQL
  add_encrypted_cookie "$db" 1 '.slack.com' d 'xoxd-encrypted%2Fvalue' / 0 1
  add_plain_cookie "$db" 2 '.slack.com' d-s 'plain-d-s%2Fvalue' / 0 1
  add_plain_cookie "$db" 3 'telepatiaworkspace.slack.com' workspace 'workspace%2Fvalue' /api 0 1
  add_plain_cookie "$db" 4 '.slack.com' insecure 'insecure%2Fvalue' /api 0 0
  add_plain_cookie "$db" 5 'slack.com' parent-host-only 'must-not-send' / 0 1
  add_plain_cookie "$db" 6 '.other.slack.com' other-domain 'must-not-send' / 0 1
  add_plain_cookie "$db" 7 '.slack.com' expired 'must-not-send' / 1 1
  add_plain_cookie "$db" 8 '.slack.com' wrong-path 'must-not-send' /other 0 1
  printf '%s\n' "$FIRST_TOKEN" "$SECOND_TOKEN" >"$profile/Local Storage/leveldb/000001.ldb"
}

export FIRST_TOKEN="xoxc-first-12345678901234567890"
export SECOND_TOKEN="xoxc-second-12345678901234567890"
export SECURITY_LOG="$TMP/security.log"
export CURL_LOG="$TMP/curl.log"
export CURL_ARGV_LOG="$TMP/curl.argv"
export JAR_CAPTURE="$TMP/cookies.txt"
export BATCH_LOG="$TMP/batches.log"

export SAVED_RESPONSE
SAVED_RESPONSE=$(cat <<'JSON'
{"ok":true,"counts":{"uncompleted_count":52,"uncompleted_overdue_count":0},"saved_items":[
{"item_id":"C01","item_type":"message","ts":"1700000001.000001","state":"saved","todo_state":"not_started","date_created":1700000001,"date_due":null},
{"item_id":"C02","item_type":"message","ts":"1700000002.000002","state":"saved","todo_state":"not_started","date_created":1700000002,"date_due":1700100002},
{"item_id":"C03","item_type":"message","ts":"1700000003.000003","state":"saved","todo_state":"not_started","date_created":1700000003,"date_due":null},
{"item_id":"C04","item_type":"message","ts":"1700000004.000004","state":"saved","todo_state":"not_started","date_created":1700000004,"date_due":null},
{"item_id":"C05","item_type":"message","ts":"1700000005.000005","state":"saved","todo_state":"not_started","date_created":1700000005,"date_due":null},
{"item_id":"C06","item_type":"message","ts":"1700000006.000006","state":"saved","todo_state":"not_started","date_created":1700000006,"date_due":null},
{"item_id":"C07","item_type":"message","ts":"1700000007.000007","state":"saved","todo_state":"not_started","date_created":1700000007,"date_due":null},
{"item_id":"C08","item_type":"message","ts":"1700000008.000008","state":"saved","todo_state":"not_started","date_created":1700000008,"date_due":null},
{"item_id":"C09","item_type":"message","ts":"1700000009.000009","state":"saved","todo_state":"not_started","date_created":1700000009,"date_due":null},
{"item_id":"C10","item_type":"message","ts":"1700000010.000010","state":"saved","todo_state":"not_started","date_created":1700000010,"date_due":null},
{"item_id":"C11","item_type":"message","ts":"1700000011.000011","state":"saved","todo_state":"not_started","date_created":1700000011,"date_due":null},
{"item_id":"F01","item_type":"file","ts":"1700000012.000012","state":"saved","todo_state":"not_started","date_created":1700000012,"date_due":null}
],"response_metadata":{"next_cursor":"next-page"}}
JSON
)

export MESSAGE_RESPONSE
MESSAGE_RESPONSE=$(cat <<'JSON'
{"ok":true,"messages":{"C01":[{"ts":"1700000001.000001","text":"One <https://example.invalid|summary>\n"}],"C02":[{"ts":"1700000002.000002","text":"Two"}],"C03":[{"ts":"1700000003.000003","text":"Three"}],"C04":[{"ts":"1700000004.000004","text":"Four"}],"C05":[{"ts":"1700000005.000005","text":"Five"}],"C06":[{"ts":"1700000006.000006","text":"Six"}],"C07":[{"ts":"1700000007.000007","text":"Seven"}],"C08":[{"ts":"1700000008.000008","text":"Eight"}],"C09":[{"ts":"1700000009.000009","text":"Nine"}],"C10":[{"ts":"1700000010.000010","text":"Ten"}],"C11":[{"ts":"1700000011.000011","text":"Eleven"}]}}
JSON
)

cat >"$TMP/bin/security" <<'EOF'
#!/usr/bin/env bash
printf 'security\n' >>"$SECURITY_LOG"
printf 'test\n'
EOF
cat >"$TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CURL_ARGV_LOG"
config=$(cat)
printf '%s\n---\n' "$config" >>"$CURL_LOG"
jar=$(printf '%s\n' "$config" | sed -n 's/^cookie = "\(.*\)"$/\1/p')
[[ -r "$jar" ]] || exit 1
cp "$jar" "$JAR_CAPTURE"
grep -Fq $'\td\txoxd-encrypted%2Fvalue' "$jar" || exit 1
grep -Fq $'\td-s\tplain-d-s%2Fvalue' "$jar" || exit 1
grep -Fq $'\tworkspace\tworkspace%2Fvalue' "$jar" || exit 1
case "$MOCK_MODE" in
  success)
    case "$config" in
      *auth.test*) printf '%s\n' '{"ok":true,"url":"https://telepatiaworkspace.slack.com/"}' ;;
      *saved.list*) printf '%s\n' "$SAVED_RESPONSE" ;;
      *messages.list*)
        message_ids=$(sed -n 's/^data-urlencode = "message_ids=\(.*\)"$/\1/p' <<<"$config")
        channel_count=$(grep -o 'channel' <<<"$message_ids" | wc -l | tr -d ' ')
        (( channel_count > 0 && channel_count <= 10 )) || exit 1
        printf '%s\n' "$channel_count" >>"$BATCH_LOG"
        printf '%s\n' "$MESSAGE_RESPONSE"
        ;;
    esac
    ;;
  wrong)
    case "$config" in
      *auth.test*) printf '%s\n' '{"ok":true,"url":"https://wrong.slack.com/"}' ;;
      *saved.list*) exit 1 ;;
    esac
    ;;
  server-error)
    case "$config" in
      *auth.test*) printf '%s\n' '{"ok":true,"url":"https://telepatiaworkspace.slack.com/"}' ;;
      *saved.list*) printf '%s\n' '{"ok":false,"error":"ratelimited"}' ;;
    esac
    ;;
  messages-error)
    case "$config" in
      *auth.test*) printf '%s\n' '{"ok":true,"url":"https://telepatiaworkspace.slack.com/"}' ;;
      *saved.list*) printf '%s\n' "$SAVED_RESPONSE" ;;
      *messages.list*) printf '%s\n' '{"ok":false,"error":"ratelimited"}' ;;
    esac
    ;;
esac
EOF
chmod +x "$TMP/bin/security" "$TMP/bin/curl"
export TMUX_SLACK_LATER_SECURITY="$TMP/bin/security"

export TMUX_SLACK_LATER_PROFILE="$TMP/missing/Default"
export TMUX_SLACK_LATER_WORKSPACE="telepatiaworkspace.slack.com"

# 0. --cached answers from disk and never fetches — this is what lets a caller
# paint before the network. Nothing has run yet, so the cache root is absent: a
# refresh that slipped in would have had to mkdir it, and would have hit curl.
: >"$CURL_LOG"
cached_cold=$(bash "$SRC" list --cached)
check "cold --cached reports loading" "loading" "$(jq -r '.error' <<<"$cached_cold")"
check "cold --cached still returns a list" "0" "$(jq '.items | length' <<<"$cached_cold")"
check "cold --cached writes no cache" "absent" \
  "$([[ -e "$TMUX_SLACK_LATER_CACHE_ROOT" ]] && echo present || echo absent)"
[[ ! -s "$CURL_LOG" ]] || {
  echo "FAIL --cached made an HTTP request" >&2
  exit 1
}
printf 'ok   cold --cached makes no HTTP request\n'
check "list rejects an unknown flag" "64" \
  "$(bash "$SRC" list --nope >/dev/null 2>&1 || echo $?)"

missing_list=$(bash "$SRC" list)
first_cache=$(cache)
check "absent profile records profile error" "profile" "$(jq -r '.error' "$first_cache")"
check "absent profile list count is zero" "0" "$(jq -r '.counts.uncompleted_count' <<<"$missing_list")"
check "absent profile list has no items" "0" "$(jq '.items | length' <<<"$missing_list")"
contains "absent profile error is visible" "!" "$(bash "$SRC" widget)"

# 2. The workspace is part of the cache key, not just the source profile.
export TMUX_SLACK_LATER_WORKSPACE="other.slack.com"
bash "$SRC" refresh
second_cache=$(cache)
[[ "$first_cache" != "$second_cache" ]] || {
  echo "FAIL workspace did not change cache namespace" >&2
  exit 1
}
check "workspace cache is independently initialized" "profile" "$(jq -r '.error' "$second_cache")"
check "first workspace cache remains intact" "profile" "$(jq -r '.error' "$first_cache")"
printf 'ok   source and workspace cache isolation\n'

# 3. A corrupt count is a red error, never a silent zero.
export TMUX_SLACK_LATER_WORKSPACE="telepatiaworkspace.slack.com"
malformed_cache=$(cache)
cat >"$malformed_cache" <<'EOF'
{"counts":{"uncompleted_count":"many","uncompleted_overdue_count":0},"error":""}
EOF
contains "malformed counts are visible" "!" "$(bash "$SRC" widget)"

# 4. Full applicable cookies (encrypted and plaintext) authenticate an exact
# workspace auth.test before saved.list. This fixture fails the former d-only
# request shape without reading Chrome, the keychain, or Slack.
export TMUX_SLACK_LATER_PROFILE="$TMP/chrome-success/Default"
create_profile "$TMUX_SLACK_LATER_PROFILE"
success_cache=$(cache)
: >"$SECURITY_LOG"
: >"$CURL_LOG"
: >"$CURL_ARGV_LOG"
: >"$BATCH_LOG"
MOCK_MODE=success PATH="$TMP/bin:$PATH" bash "$SRC" refresh
check "full cookie request publishes 52" "52" "$(jq -r '.counts.uncompleted_count' "$success_cache")"
check "full cookie request clears error" "" "$(jq -r '.error' "$success_cache")"
check "full cookie request stores every saved item" "12" "$(jq '.items | length' "$success_cache")"
check "message id combines channel and timestamp" "C01:1700000001.000001" "$(jq -r '.items[0].id' "$success_cache")"
check "message title is compact and sanitized" "One summary" "$(jq -r '.items[0].title' "$success_cache")"
check "message url is stable" "https://telepatiaworkspace.slack.com/archives/C01/p1700000001000001" "$(jq -r '.items[0].url' "$success_cache")"
check "unresolved non-message uses fallback title" "Message unavailable" "$(jq -r '.items[11].title' "$success_cache")"
check "unresolved non-message uses workspace url" "https://telepatiaworkspace.slack.com" "$(jq -r '.items[11].url' "$success_cache")"
check "cursor marks bounded result truncated" "true" "$(jq -r '.truncated' "$success_cache")"
check "cache is private" "600" "$(/usr/bin/stat -f '%Lp' "$success_cache")"
check "derives Chrome key once" "1" "$(wc -l <"$SECURITY_LOG" | tr -d ' ')"
contains "request uses workspace host" 'url = "https://telepatiaworkspace.slack.com/api/auth.test"' "$(cat "$CURL_LOG")"
contains "request posts supported saved limit 49" 'data-urlencode = "limit=49"' "$(cat "$CURL_LOG")"
contains "request URLencodes message ids" 'data-urlencode = "message_ids=[{\"channel\":\"C01\"' "$(cat "$CURL_LOG")"
check "message hydration has two channel batches" $'10\n1' "$(cat "$BATCH_LOG")"
contains "request uses Chrome user agent" 'Chrome/123.0.0.0 Safari' "$(cat "$CURL_LOG")"
not_contains "request does not use bearer auth" "Authorization:" "$(cat "$CURL_LOG")"
contains "jar preserves encrypted d" $'\td\txoxd-encrypted%2Fvalue' "$(cat "$JAR_CAPTURE")"
contains "jar preserves plaintext d-s" $'\td-s\tplain-d-s%2Fvalue' "$(cat "$JAR_CAPTURE")"
contains "jar keeps workspace cookie" $'\tworkspace\tworkspace%2Fvalue' "$(cat "$JAR_CAPTURE")"
contains "jar preserves insecure metadata" $'\tFALSE\t0\tinsecure\tinsecure%2Fvalue' "$(cat "$JAR_CAPTURE")"
not_contains "jar excludes parent host-only cookie" "parent-host-only" "$(cat "$JAR_CAPTURE")"
not_contains "jar excludes other domain" "other-domain" "$(cat "$JAR_CAPTURE")"
not_contains "jar excludes expired cookie" "expired" "$(cat "$JAR_CAPTURE")"
not_contains "jar excludes non-api path" "wrong-path" "$(cat "$JAR_CAPTURE")"
if grep -Eq 'xox[c,d]-|plain-d-s|workspace%2Fvalue' "$CURL_ARGV_LOG"; then
  echo "FAIL credentials appeared in curl argv" >&2
  exit 1
fi
printf 'ok   curl argv excludes credentials\n'

: >"$CURL_LOG"
fresh_list=$(MOCK_MODE=success PATH="$TMP/bin:$PATH" bash "$SRC" list)
check "fresh list returns cached title" "One summary" "$(jq -r '.items[0].title' <<<"$fresh_list")"
[[ ! -s "$CURL_LOG" ]] || {
  echo "FAIL fresh list made an HTTP request" >&2
  exit 1
}
printf 'ok   fresh list makes no HTTP request\n'

# A stale cache is precisely the case plain `list` spends a refresh on. --cached
# hands the stale rows over untouched instead, which is a caller's first frame.
touch -t 200001010000 "$success_cache"
: >"$CURL_LOG"
stale_cached=$(MOCK_MODE=success PATH="$TMP/bin:$PATH" bash "$SRC" list --cached)
check "stale --cached serves the stale rows" "12" "$(jq '.items | length' <<<"$stale_cached")"
check "stale --cached does not mark them loading" "" "$(jq -r '.error' <<<"$stale_cached")"
[[ ! -s "$CURL_LOG" ]] || {
  echo "FAIL stale --cached made an HTTP request" >&2
  exit 1
}
printf 'ok   stale --cached makes no HTTP request\n'

cat >"$success_cache" <<'EOF'
{"counts":{"uncompleted_count":52,"uncompleted_overdue_count":0},"error":""}
EOF
: >"$CURL_LOG"
: >"$BATCH_LOG"
count_only_list=$(MOCK_MODE=success PATH="$TMP/bin:$PATH" bash "$SRC" list)
check "count-only cache hydrates rows" "12" "$(jq '.items | length' <<<"$count_only_list")"
check "count-only cache refreshes saved list" "1" "$(grep -c saved.list "$CURL_LOG" | tr -d ' ')"
check "count-only cache hydrates in batches" $'10\n1' "$(cat "$BATCH_LOG")"

export TMUX_SLACK_LATER_PROFILE="$TMP/chrome-wrong/Default"
create_profile "$TMUX_SLACK_LATER_PROFILE"
wrong_cache=$(cache)
: >"$CURL_LOG"
MOCK_MODE=wrong PATH="$TMP/bin:$PATH" bash "$SRC" refresh
check "wrong workspace publishes credentials error" "credentials" "$(jq -r '.error' "$wrong_cache")"
contains "wrong workspace calls auth.test" "auth.test" "$(cat "$CURL_LOG")"
not_contains "wrong workspace skips saved.list" "saved.list" "$(cat "$CURL_LOG")"

export TMUX_SLACK_LATER_PROFILE="$TMP/chrome-server-error/Default"
create_profile "$TMUX_SLACK_LATER_PROFILE"
server_error_cache=$(cache)
: >"$CURL_LOG"
MOCK_MODE=server-error PATH="$TMP/bin:$PATH" bash "$SRC" refresh
check "server error is visible" "network" "$(jq -r '.error' "$server_error_cache")"
contains "first candidate was attempted" "$FIRST_TOKEN" "$(cat "$CURL_LOG")"
not_contains "server error stops second candidate" "$SECOND_TOKEN" "$(cat "$CURL_LOG")"

export TMUX_SLACK_LATER_PROFILE="$TMP/chrome-success/Default"
preserved_items=$(jq -c '.items' "$success_cache")
: >"$CURL_LOG"
MOCK_MODE=messages-error PATH="$TMP/bin:$PATH" bash "$SRC" refresh
check "hydration failure is visible" "network" "$(jq -r '.error' "$success_cache")"
check "hydration failure preserves rows" "$preserved_items" "$(jq -c '.items' "$success_cache")"
contains "hydration attempts first candidate" "$FIRST_TOKEN" "$(cat "$CURL_LOG")"
not_contains "hydration does not probe second candidate" "$SECOND_TOKEN" "$(cat "$CURL_LOG")"

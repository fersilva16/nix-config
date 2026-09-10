#!/usr/bin/env bash
# Offline-safe Slack Later refresh/widget implementation. The Nix wrappers set
# PROFILE and WORKSPACE; tests can override the cache roots without opening
# Chrome, the keychain, or the network.
set -uo pipefail

PROFILE=${TMUX_SLACK_LATER_PROFILE:-}
WORKSPACE=${TMUX_SLACK_LATER_WORKSPACE:-}
CACHE_ROOT=${TMUX_SLACK_LATER_CACHE_ROOT:-"${XDG_CACHE_HOME:-$HOME/.cache}/tmux-slack-later"}
PRIVATE_TMP=
WORKSPACE=${WORKSPACE,,}
CONFIG_ERROR=
case "$WORKSPACE" in
  *[!a-z0-9.-]* | "") CONFIG_ERROR=workspace ;;
esac
[[ -n "$PROFILE" ]] || CONFIG_ERROR=profile
NAMESPACE=
CACHE=

configure() {
  [[ -z "$CONFIG_ERROR" ]] || return 1
  NAMESPACE=$(printf '%s\0%s' "$PROFILE" "$WORKSPACE" | sha256sum | awk '{ print $1 }')
  CACHE="$CACHE_ROOT/$NAMESPACE.json"
}

cleanup() {
  [[ -z "$PRIVATE_TMP" ]] || rm -rf "$PRIVATE_TMP"
  unset CHROME_SAFE_STORAGE_PASSWORD
}

trap cleanup EXIT
trap 'cleanup; exit 1' HUP INT TERM

valid_counts() {
  jq -ce '
    def count: type == "number" and . >= 0 and floor == .;
    if (.counts | type == "object")
      and (.counts.uncompleted_count | count)
      and (.counts.uncompleted_overdue_count | count)
    then {
      uncompleted_count: .counts.uncompleted_count,
      uncompleted_overdue_count: .counts.uncompleted_overdue_count
    }
    else empty
    end
  '
}

valid_list() {
  jq -ce '
    def count: type == "number" and . >= 0 and floor == .;
    def date: . == null or type == "number" or type == "string";
    def item:
      type == "object"
      and (.id | type == "string")
      and (.title | type == "string")
      and (.url | type == "string")
      and (.date_created | date)
      and (.date_due | date);
    if (.counts | type == "object")
      and (.counts.uncompleted_count | count)
      and (.counts.uncompleted_overdue_count | count)
      and (.items | type == "array")
      and all(.items[]; item)
      and (.error | type == "string")
      and (.truncated | type == "boolean")
    then {
      counts: {
        uncompleted_count: .counts.uncompleted_count,
        uncompleted_overdue_count: .counts.uncompleted_overdue_count
      },
      items: [.items[] | {
        id: .id,
        title: .title,
        url: .url,
        date_created: .date_created,
        date_due: .date_due
      }],
      error: .error,
      truncated: .truncated
    }
    else empty
    end
  '
}

empty_list() {
  jq -cn --arg error "$1" '{
    counts: { uncompleted_count: 0, uncompleted_overdue_count: 0 },
    items: [],
    error: $error,
    truncated: false
  }'
}

write_cache() {
  local list=$1 output
  output=$(mktemp "$PRIVATE_TMP/cache.XXXXXX") || return 1
  if valid_list <<<"$list" >"$output"; then
    chmod 600 "$output" || return 1
    mv "$output" "$CACHE"
  else
    rm -f "$output"
    return 1
  fi
}

publish() {
  local list
  list=$(valid_list) || return 1
  write_cache "$list"
}

publish_error() {
  local reason=$1 counts list
  counts=$(valid_counts <"$CACHE" 2>/dev/null) || {
    counts='{"uncompleted_count":0,"uncompleted_overdue_count":0}'
  }
  if ! list=$(valid_list <"$CACHE" 2>/dev/null); then
    list=$(jq -cn --argjson counts "$counts" --arg error "$reason" '{
      counts: $counts,
      items: [],
      error: $error,
      truncated: false
    }') || return 1
  else
    list=$(jq -c --arg error "$reason" '.error = $error' <<<"$list") || return 1
  fi
  write_cache "$list"
}

cache_fresh() {
  [[ -f "$CACHE" ]] && find "$CACHE" -mmin -15 2>/dev/null | grep -q .
}

cache_has_items() {
  valid_list <"$CACHE" >/dev/null 2>&1
}

# 2>/dev/null before the input redirect, not after: an absent cache is a normal
# --cached state, and bash reports a failed redirect against whatever stderr is
# at that point in the line.
emit_list() {
  valid_list 2>/dev/null <"$CACHE" || empty_list "${1:-cache}"
}

cookie_database() {
  local candidate
  for candidate in "$PROFILE/Network/Cookies" "$PROFILE/Cookies"; do
    [[ -f "$candidate" ]] && {
      printf '%s' "$candidate"
      return 0
    }
  done
  return 1
}

safe_token() {
  [[ $1 =~ ^xoxc-[0-9A-Za-z-]{20,}$ ]]
}

safe_jar_field() {
  [[ $1 != *$'\t'* && $1 != *$'\r'* && $1 != *$'\n'* ]]
}

cookie_path_matches() {
  local cookie_path=$1 request_path=$2
  [[ $cookie_path == /* && $request_path == "$cookie_path"* ]] || return 1
  [[ $cookie_path == / || $cookie_path == */ || ${request_path:${#cookie_path}:1} == / ]]
}

workspace_cookie_domain() {
  local domain=$1 suffix
  case "$domain" in
    "$WORKSPACE") return 0 ;;
    .*)
      suffix=${domain#.}
      [[ $WORKSPACE == "$suffix" || $WORKSPACE == *."$suffix" ]]
      ;;
    *) return 1 ;;
  esac
}

derive_key() {
  local password key security=${TMUX_SLACK_LATER_SECURITY:-/usr/bin/security}

  [[ $security == /* && -x $security ]] || return 1
  password=$("$security" find-generic-password -w \
    -s "Chrome Safe Storage" -a "Chrome" 2>/dev/null) || return 1
  [[ -n "$password" ]] || return 1

  # OpenSSL reads the password from its environment, not a process argument.
  export CHROME_SAFE_STORAGE_PASSWORD=$password
  key=$(openssl enc -aes-128-cbc -P -md sha1 -iter 1003 -saltlen 9 \
    -pass env:CHROME_SAFE_STORAGE_PASSWORD \
    -S 73616c747973616c74 2>/dev/null | awk -F= '/^key=/{ print $2 }')
  unset CHROME_SAFE_STORAGE_PASSWORD
  [[ $key =~ ^[0-9A-Fa-f]{32}$ ]] || return 1
  printf '%s' "$key"
}

decrypt_cookie() {
  local key=$1 db=$2 rowid=$3 domain=$4 schema=$5 blob plaintext domain_hash actual_hash

  [[ $rowid =~ ^[0-9]+$ ]] || return 1
  blob="$PRIVATE_TMP/cookie-$rowid.blob"
  plaintext="$PRIVATE_TMP/cookie-$rowid.plaintext"
  domain_hash="$PRIVATE_TMP/cookie-$rowid.domain.hash"
  actual_hash="$PRIVATE_TMP/cookie-$rowid.actual.hash"
  sqlite3 "$db" \
    "select writefile('$blob', encrypted_value) from cookies where rowid = $rowid;" \
    >/dev/null 2>&1 || return 1
  [[ -s "$blob" ]] || return 1

  case "$(head -c 3 "$blob")" in
    v10 | v11) ;;
    *) return 1 ;;
  esac

  # No -nopad: OpenSSL removes PKCS#7 padding normally. Chromium's v24 domain
  # hash is checked before the cookie value is emitted into the private jar.
  tail -c +4 "$blob" | openssl enc -aes-128-cbc -d -K "$key" \
    -iv 20202020202020202020202020202020 >"$plaintext" 2>/dev/null || return 1
  if (( schema >= 24 )); then
    printf '%s' "$domain" | openssl dgst -sha256 -binary >"$domain_hash"
    head -c 32 "$plaintext" >"$actual_hash"
    cmp -s "$domain_hash" "$actual_hash" || return 1
    tail -c +33 "$plaintext"
  else
    cat "$plaintext"
  fi
}

extract_cookie_jar() {
  local source_db=$1 db jar key schema now_chrome rowid domain path secure expires name value encrypted_len
  local cookie include_subdomains unix_expiry count=0

  # sqlite's backup API gives a consistent snapshot of Chrome's live database.
  db="$PRIVATE_TMP/cookies.sqlite"
  jar="$PRIVATE_TMP/cookies.txt"
  sqlite3 "$source_db" ".backup '$db'" >/dev/null 2>&1 || return 1
  schema=$(sqlite3 "$db" "select value from meta where key = 'version';" 2>/dev/null) || return 1
  [[ $schema =~ ^[0-9]+$ ]] || return 1

  # One Chrome Safe Storage derivation covers every encrypted row in this
  # extraction. Plaintext rows still enter the same workspace-scoped jar.
  key=$(derive_key) || return 1
  now_chrome=$(( $(date +%s) * 1000000 + 11644473600000000 ))
  printf '# Netscape HTTP Cookie File\n' >"$jar"

  while IFS=$'\x1f' read -r rowid domain path secure expires name value encrypted_len; do
    workspace_cookie_domain "$domain" || continue
    cookie_path_matches "$path" /api/ || continue
    [[ $secure == 0 || $secure == 1 ]] || continue
    [[ $expires =~ ^[0-9]+$ && $encrypted_len =~ ^[0-9]+$ ]] || continue
    if [[ -z $name ]] || ! safe_jar_field "$name" || ! safe_jar_field "$value"; then
      continue
    fi

    if [[ -n $value ]]; then
      cookie=$value
    elif (( encrypted_len > 0 )); then
      cookie=$(decrypt_cookie "$key" "$db" "$rowid" "$domain" "$schema") || continue
      safe_jar_field "$cookie" || continue
    else
      continue
    fi

    if [[ $domain == .* ]]; then
      include_subdomains=TRUE
    else
      include_subdomains=FALSE
    fi
    if (( expires == 0 )); then
      unix_expiry=0
    else
      (( expires > now_chrome )) || continue
      unix_expiry=$((expires / 1000000 - 11644473600))
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$domain" "$include_subdomains" "$path" \
      "$([[ $secure == 1 ]] && printf TRUE || printf FALSE)" \
      "$unix_expiry" "$name" "$cookie" >>"$jar"
    ((count += 1))
  done < <(
    sqlite3 -separator $'\x1f' "$db" "
      select rowid, host_key, path, is_secure, expires_utc, name,
        coalesce(value, ''), length(encrypted_value)
      from cookies
      where host_key = '$WORKSPACE'
        or (substr(host_key, 1, 1) = '.' and '$WORKSPACE' like '%' || host_key)
      order by length(path) desc, creation_utc asc;
    " 2>/dev/null
  )

  (( count > 0 )) || return 1
  printf '%s' "$jar"
}

chrome_user_agent() {
  local version=${TMUX_SLACK_LATER_CHROME_VERSION:-}
  if [[ -z "$version" ]]; then
    version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
      '/Applications/Google Chrome.app/Contents/Info.plist' 2>/dev/null) || return 1
  fi
  [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  printf 'Mozilla/5.0 (Macintosh; arm Mac OS X 14_0_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/%s Safari/537.36' "$version"
}

curl_config_value() {
  local value=$1
  [[ $value != *$'\r'* && $value != *$'\n'* ]] || return 1
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  printf '%s' "$value"
}

# Credentials live only in the private Netscape jar. Curl receives its path in
# stdin config, while token and cookies never appear in curl's command line.
slack_request() {
  local endpoint=$1 token=$2 jar=$3 message_ids=${4:-} user_agent escaped_message_ids
  safe_token "$token" && [[ -r "$jar" ]] || return 1
  case "$endpoint" in
    auth.test | saved.list) ;;
    messages.list) [[ -n "$message_ids" ]] || return 1 ;;
    *) return 1 ;;
  esac
  user_agent=$(chrome_user_agent) || return 1
  if [[ $endpoint == messages.list ]]; then
    escaped_message_ids=$(curl_config_value "$message_ids") || return 1
  fi

  {
    cat <<EOF
url = "https://$WORKSPACE/api/$endpoint"
request = "POST"
connect-timeout = 5
max-time = 15
user-agent = "$user_agent"
cookie = "$jar"
data-urlencode = "token=$token"
EOF
    case "$endpoint" in
      saved.list)
        cat <<'EOF'
data-urlencode = "limit=49"
data-urlencode = "filter=saved"
EOF
        ;;
      messages.list) printf 'data-urlencode = "message_ids=%s"\n' "$escaped_message_ids" ;;
    esac
  } | curl --silent --show-error --config -
}

call_saved() {
  local response error
  response=$(slack_request "saved.list" "$1" "$2") || return 2
  error=$(printf '%s' "$response" | jq -r 'if .ok then "" else (.error // "malformed") end' 2>/dev/null) || return 2
  case "$error" in
    "") printf '%s' "$response" ;;
    invalid_auth | not_authed | token_revoked | token_expired) return 1 ;;
    *) return 2 ;;
  esac
}

call_messages() {
  local response error
  response=$(slack_request "messages.list" "$1" "$2" "$3") || return 1
  error=$(printf '%s' "$response" | jq -r 'if .ok then "" else (.error // "malformed") end' 2>/dev/null) || return 1
  [[ -z "$error" ]] || return 1
  printf '%s' "$response" | jq -ce '.messages | type == "object"' >/dev/null || return 1
  printf '%s' "$response"
}

valid_saved_response() {
  jq -e '
    def count: type == "number" and . >= 0 and floor == .;
    .ok == true
    and (.counts | type == "object")
    and (.counts.uncompleted_count | count)
    and (.counts.uncompleted_overdue_count | count)
    and (.saved_items | type == "array")
  ' >/dev/null
}

hydration_batches() {
  jq -cr '
    def channel: type == "string" and test("^[A-Z][A-Z0-9]+$");
    def timestamp: type == "string" and test("^[0-9]+\\.[0-9]+$");
    [.saved_items[]?
      | select(.item_type == "message" and (.item_id | channel) and (.ts | timestamp))
      | { channel: .item_id, timestamp: .ts }]
    | group_by(.channel)
    | [range(0; length; 10) as $start
      | .[$start:($start + 10)]
      | map({ channel: .[0].channel, timestamps: map(.timestamp) })][]
  '
}

materialize_saved() {
  local saved=$1 messages=$2
  jq -ce --arg workspace "$WORKSPACE" --slurpfile messages "$messages" '
    def channel: type == "string" and test("^[A-Z][A-Z0-9]+$");
    def timestamp: type == "string" and test("^[0-9]+\\.[0-9]+$");
    def date: type == "number" or type == "string";
    def clean_title:
      gsub("<[^>|]+\\|(?<label>[^>]+)>"; "\(.label)")
      | gsub("[[:cntrl:]]"; " ")
      | gsub("[[:space:]]+"; " ")
      | gsub("^[[:space:]]+|[[:space:]]+$"; "")
      | .[0:300]
      | if length == 0 then "Message unavailable" else . end;
    def message_text($channel; $timestamp):
      [$messages[0][$channel][]?
        | select((.ts? | type) == "string" and .ts == $timestamp)
        | .text? | select(type == "string")][0] // "";
    {
      counts: {
        uncompleted_count: .counts.uncompleted_count,
        uncompleted_overdue_count: .counts.uncompleted_overdue_count
      },
      items: [
        .saved_items | to_entries[]
        | .key as $index | .value
        | . as $item
        | ($item.item_id? // null) as $channel
        | ($item.ts? // null) as $timestamp
        | {
          id: (if ($channel | channel) and ($timestamp | timestamp)
            then "\($channel):\($timestamp)"
            else "item:\($index)"
            end),
          title: (if $item.item_type == "message"
              and ($channel | channel) and ($timestamp | timestamp)
            then message_text($channel; $timestamp) | clean_title
            else "Message unavailable"
            end),
          url: (if $item.item_type == "message"
              and ($channel | channel) and ($timestamp | timestamp)
            then "https://\($workspace)/archives/\($channel)/p\($timestamp | gsub("\\."; ""))"
            else "https://\($workspace)"
            end),
          date_created: (if ($item.date_created? | date) then $item.date_created else null end),
          date_due: (if ($item.date_due? | date) then $item.date_due else null end)
        }
      ],
      error: "",
      truncated: ((.response_metadata? | type) == "object"
        and (.response_metadata.next_cursor? | type) == "string"
        and .response_metadata.next_cursor != "")
    }
  ' <<<"$saved"
}

hydrate_saved() {
  local token=$1 jar=$2 saved=$3 messages response response_file next
  valid_saved_response <<<"$saved" || return 1
  messages="$PRIVATE_TMP/messages.json"
  printf '{}' >"$messages"

  while IFS= read -r batch; do
    [[ -n "$batch" ]] || continue
    response=$(call_messages "$token" "$jar" "$batch") || return 1
    response_file=$(mktemp "$PRIVATE_TMP/messages-response.XXXXXX") || return 1
    next="$PRIVATE_TMP/messages-next.json"
    printf '%s' "$response" >"$response_file"
    jq -ce -s '.[0] + .[1].messages' "$messages" "$response_file" >"$next" || return 1
    mv "$next" "$messages"
  done < <(hydration_batches <<<"$saved")

  materialize_saved "$saved" "$messages"
}

# Return 0 only for the exact configured URL host; no team-name/id/substrings.
workspace_ok() {
  local response
  response=$(slack_request "auth.test" "$1" "$2") || return 2
  printf '%s' "$response" | jq -e --arg workspace "$WORKSPACE" '
    .ok == true
    and (.url | type == "string")
    and ((.url | capture("^https://(?<host>[A-Za-z0-9.-]+)(?:/|$)").host | ascii_downcase) == $workspace)
  ' >/dev/null 2>&1
}

candidates() {
  local leveldb=$PROFILE/Local\ Storage/leveldb file
  [[ -d "$leveldb" ]] || return 0
  # This is a bounded raw-binary grep, not a LevelDB parser. No result only
  # means no usable plaintext token was found in this limited scan; it does not
  # mean Chrome or Slack is signed out.
  while IFS= read -r file; do
    grep -a -o -m 16 'xoxc-[0-9A-Za-z-]\{20,\}' "$file" 2>/dev/null
  done < <(
    find "$leveldb" -maxdepth 1 -type f \( -name '*.ldb' -o -name '*.log' \) -print 2>/dev/null \
      | sort | head -n 32
  ) | sort -u | head -n 8
}

resolve() {
  local jar=$1 tokens=$2 token response status
  while IFS= read -r token; do
    [[ -n "$token" ]] || continue
    workspace_ok "$token" "$jar"
    status=$?
    case "$status" in
      0) ;;
      2) return 2 ;;
      *) continue ;;
    esac
    if response=$(call_saved "$token" "$jar"); then
      response=$(hydrate_saved "$token" "$jar" "$response") || return 2
      printf '%s' "$response"
      return 0
    else
      status=$?
      (( status == 2 )) && return 2
    fi
  done <<<"$tokens"
  return 1
}

refresh() {
  local db tokens jar response="" status

  umask 077
  mkdir -p "$CACHE_ROOT" || return 1
  chmod 700 "$CACHE_ROOT" || return 1
  PRIVATE_TMP=$(mktemp -d "${TMPDIR:-/tmp}/tmux-slack-later.XXXXXX") || return 1
  touch "$CACHE" || return 1
  chmod 600 "$CACHE" || return 1

  db=$(cookie_database) || {
    publish_error "profile"
    return 0
  }
  tokens=$(candidates)
  [[ -n "$tokens" ]] || {
    publish_error "credentials"
    return 0
  }
  jar=$(extract_cookie_jar "$db") || {
    publish_error "credentials"
    return 0
  }

  if response=$(resolve "$jar" "$tokens"); then
    publish <<<"$response" || publish_error "response"
    return 0
  else
    status=$?
  fi
  (( status == 2 )) && {
    publish_error "network"
    return 0
  }
  publish_error "credentials"
}

# --cached never fetches. A stale or absent cache is something a caller can put
# on screen now and correct later, so the wait for a real refresh — minutes, in
# the worst case — belongs to a caller that asked for one, not to a first paint.
list() {
  if [[ ${1:-} == --cached ]]; then
    emit_list loading
    return
  fi
  if ! cache_fresh || ! cache_has_items; then
    refresh || true
  fi
  emit_list
}

widget() {
  local state n overdue error mark color
  local bg="#f2f0e5" fg="#100f0f" red="#d14d41"
  local reset="#[fg=$fg,bg=$bg,nobold,noitalics,nounderscore,nodim]"
  local slack

  slack=$(printf '\uF198')
  if ! find "$CACHE" -mmin -15 2>/dev/null | grep -q .; then
    tmux-slack-later-refresh >/dev/null 2>&1 &
  fi
  [[ -f "$CACHE" ]] || return 0

  state=$(jq -r '
    def count: type == "number" and . >= 0 and floor == .;
    if (.counts | type == "object")
      and (.counts.uncompleted_count | count)
      and (.counts.uncompleted_overdue_count | count)
    then [
      (.counts.uncompleted_count | tostring),
      (.counts.uncompleted_overdue_count | tostring),
      (if .error == null or .error == "" then "" elif (.error | type) == "string" then .error else "malformed" end)
    ]
    else ["0", "0", "malformed"]
    end | @tsv
  ' "$CACHE" 2>/dev/null) || state=$'0\t0\tmalformed'
  IFS=$'\t' read -r n overdue error <<<"$state"
  case "$n" in "" | *[!0-9]*) n=0; error=${error:-malformed} ;; esac
  case "$overdue" in "" | *[!0-9]*) overdue=0; error=${error:-malformed} ;; esac

  mark=""
  [[ -z "$error" ]] || mark=" #[fg=$red]!"
  [[ $n -gt 0 || -n "$mark" ]] || return 0
  [[ $overdue -gt 0 ]] && color=$red || color=$fg
  printf '#[fg=%s,bg=%s,bold] %s %s%s%s \n' "$color" "$bg" "$slack" "$n" "$mark" "$reset"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  case ${1:-} in
    refresh | widget)
      configure || exit 64
      "$1"
      ;;
    list)
      case ${2:-} in "" | --cached) ;; *) exit 64 ;; esac
      if configure; then
        list "${2:-}"
      else
        empty_list "${CONFIG_ERROR:-configuration}"
      fi
      ;;
    *) exit 64 ;;
  esac
fi

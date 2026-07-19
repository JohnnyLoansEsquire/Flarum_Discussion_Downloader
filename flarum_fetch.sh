#!/usr/bin/env bash
#
# flarum_fetch.sh
#
# Fetches every post in a Flarum discussion and combines them into a single
# readable text file, bypassing the frontend's virtualized infinite scroll.
#
# USAGE:
#   ./flarum_fetch.sh <discussion_url>
#
# EXAMPLES:
#   ./flarum_fetch.sh https://discuss.grapheneos.org/d/9344-chat-platforms
#   ./flarum_fetch.sh https://discuss.grapheneos.org/d/9344-chat-platforms/4
#
# REQUIREMENTS: bash, wget, jq, sed, grep, date
#
set -euo pipefail

# --- Verify required external commands are available -----------------------
assert_cmds() {
  local missing_cmds=()

  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing_cmds+=("$cmd")
    fi
  done

  if [ "${#missing_cmds[@]}" -gt '0' ]; then
    printf "You are missing the following commands which are required for this script:\n"
    for cmd in "${missing_cmds[@]}"; do
      printf "  * %s\n" "$cmd"
    done
    exit 1
  fi
}

assert_cmds wget jq sed grep date

# --- Detect GNU/Linux vs BSD (macOS) date, since their flags aren't compatible ----
# GNU date supports `--version`; BSD/macOS date does not.
if date --version >/dev/null 2>&1; then
  date_is_gnu=1
else
  date_is_gnu=0
fi

# Converts a Flarum "createdAt" UTC timestamp (e.g. 2024-06-01T12:34:56Z or
# 2024-06-01T12:34:56+00:00) into "HH:MM YYYY-MM-DD" in the local timezone,
# on both GNU/Linux and BSD (macOS) date implementations.
to_local_time() {
  local created="$1"

  if [ "$date_is_gnu" -eq 1 ]; then
    date -d "$created" "+%H:%M %Y-%m-%d"
  else
    local stripped epoch
    # Drop fractional seconds and any trailing timezone marker (Z or +HH:MM),
    # since BSD date's -f parsing needs an exact, fixed format string and we
    # know Flarum's timestamps are UTC.
    stripped=$(echo "$created" | sed -E 's/\.[0-9]+//; s/(Z|[+-][0-9]{2}:?[0-9]{2})$//')
    if ! epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" "+%s" 2>/dev/null); then
      echo "unknown-time"
      return
    fi
    date -r "$epoch" "+%H:%M %Y-%m-%d"
  fi
}

if [ $# -lt 1 ]; then
  echo "Usage: $0 <flarum-discussion-url>"
  echo "Example: $0 https://discuss.grapheneos.org/d/9344-chat-platforms"
  exit 1
fi

input_url="$1"

# --- Extract base domain (scheme + host) -----------------------------------
base_url=$(echo "$input_url" | grep -oE '^https?://[^/]+')
if [ -z "$base_url" ]; then
  echo "Error: could not parse domain from URL: $input_url"
  exit 1
fi

# --- Extract discussion ID ---------------------------------------------------
# Matches the first run of digits that appears right after '/d/'
discussion_id=$(echo "$input_url" | grep -oE '/d/[0-9]+' | head -1 | grep -oE '[0-9]+')
if [ -z "$discussion_id" ]; then
  echo "Error: could not find a discussion ID (expected .../d/<number>-<Discussion_Title>) (e.g. https://discuss.grapheneos.org/d/9344-chat-platforms) in URL: $input_url"
  exit 1
fi

echo "Domain:        $base_url"
echo "Discussion ID: $discussion_id"
echo

# --- Work in a dedicated directory per discussion ---------------------------
workdir="flarum_discussion_${discussion_id}"
mkdir -p "$workdir/posts"
cd "$workdir"

# --- Step 1: fetch the discussion resource to get the full list of post IDs -
echo "[1/4] Fetching discussion metadata and post ID list..."
discussion_json="discussion_${discussion_id}.json"
wget -q "${base_url}/api/discussions/${discussion_id}?include=posts" -O "$discussion_json"

if ! jq -e '.data' "$discussion_json" >/dev/null 2>&1; then
  echo "Error: unexpected response fetching discussion. Contents:"
  cat "$discussion_json"
  exit 1
fi

title=$(jq -r '.data.attributes.title' "$discussion_json")
jq -r '.data.relationships.posts.data[]?.id' "$discussion_json" > post_ids.txt

total_ids=$(wc -l < post_ids.txt | tr -d ' ')
echo "      Discussion: \"$title\""
echo "      Total post IDs found:         $total_ids"
echo

if [ "$total_ids" -eq 0 ]; then
  echo "No post IDs found — nothing to fetch. Exiting."
  exit 1
fi

# --- Step 2: fetch each post individually -----------------------------------
echo "[2/4] Fetching each post individually (polite 0.3s delay between requests)..."
count=0
while read -r id; do
  [ -z "$id" ] && continue
  out="posts/post_${id}.json"
  if [ -f "$out" ]; then
    # Already fetched in a previous run of this script — skip re-downloading.
    continue
  fi
  wget -q "${base_url}/api/posts/${id}" -O "$out"
  count=$((count + 1))
  if [ $((count % 20)) -eq 0 ]; then
    echo "      ...fetched $count / $total_ids"
  fi
  sleep 0.3
done < post_ids.txt
echo "      Done fetching. ($count new requests made this run)"
echo

# --- Step 3: report successes vs failures/deleted posts ----------------------
echo "[3/4] Checking results..."
success_count=$( (grep -L '"errors"' posts/*.json || true) | wc -l | tr -d ' ')
failed_files=$(grep -l '"errors"' posts/*.json 2>/dev/null || true)
failed_count=$(echo -n "$failed_files" | grep -c . || true)

echo "      Successful posts: $success_count"
echo "      Failed posts: $failed_count"
if [ "$failed_count" -gt 0 ]; then
  echo "      Failed IDs:"
  for f in $failed_files; do
    basename "$f" .json | sed 's/post_//'
  done | sed 's/^/        - /'
fi
echo

# --- Step 4: combine into one sorted, readable text file ---------------------
echo "[4/4] Combining posts into a single, readable file"

# Build a JSON array of only the successful post objects, sorted by post number.
# Each element also resolves the author's displayName from that post's
# "included" users array (Flarum includes the post author by default).
jq -s '
  map(select(has("errors") | not)) |
  map(
    (.included // []) as $inc |
    .data as $d |
    ($d.relationships.user.data.id? // null) as $uid |
    (
      (if $uid == null then null
       else ($inc[] | select(.type=="users" and .id==$uid) | .attributes.displayName)
       end) // "Unknown"
    ) as $dname |
    {
      number: $d.attributes.number,
      createdAt: $d.attributes.createdAt,
      contentHtml: $d.attributes.contentHtml,
      displayName: $dname
    }
  ) |
  sort_by(.number)
' posts/*.json > all_posts_sorted.json

# Build the output filename as "<discussion title>_<discussion id>.txt",
# sanitizing characters that aren't safe in filenames.
safe_title=$(echo "$title" | sed 's/[\/\\:*?"<>|]/_/g')
outfile="../${safe_title}_${discussion_id}.txt"

{
  echo "Discussion: $title"
  echo "URL: ${base_url}/d/${discussion_id}"
  echo "Total posts retrieved: $success_count (of $total_ids listed, $failed_count unavailable)"
  echo "======================================================================"
  echo
} > "$outfile"

# Emit each post, converting createdAt (UTC) to the local machine's timezone
# and formatting it as "HH:MM YYYY-MM-DD".
jq -c '.[]' all_posts_sorted.json | while IFS= read -r post_json; do
  num=$(echo "$post_json" | jq -r '.number')
  created=$(echo "$post_json" | jq -r '.createdAt')
  dname=$(echo "$post_json" | jq -r '.displayName')
  content=$(echo "$post_json" | jq -r '.contentHtml')
  localtime=$(to_local_time "$created")

  {
    echo "--- Post #${num} - ${dname} (${localtime}) ---"
    echo "$content" | sed -e 's/<[^>]*>//g'
    echo
  } >> "$outfile"
done

echo
echo "======================================================================"
echo "All done."
echo "Combined, searchable text file created at:"
echo "  $(cd .. && pwd)/${safe_title}_${discussion_id}.txt"
echo "======================================================================"

# Comment the next 3 lines to retain intermediary files for debugging
cd ..
rm -- "$workdir"/*.json
rm -- "$workdir"/*.txt

# Uncomment the next 2 lines to delete all temp files (Later runs on the same discussion requires downloading each comment again)
#cd ..
#rm -rf -- "$workdir"

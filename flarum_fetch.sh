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
# REQUIREMENTS: bash, wget, jq, sed
#
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <flarum-discussion-url>"
  echo "Example: $0 https://discuss.grapheneos.org/d/9344-chat-platforms"
  exit 1
fi

INPUT_URL="$1"

# --- Extract base domain (scheme + host) -----------------------------------
BASE_URL=$(echo "$INPUT_URL" | grep -oE '^https?://[^/]+')
if [ -z "$BASE_URL" ]; then
  echo "Error: could not parse domain from URL: $INPUT_URL"
  exit 1
fi

# --- Extract discussion ID ---------------------------------------------------
# Matches the first run of digits that appears right after '/d/'
DISCUSSION_ID=$(echo "$INPUT_URL" | grep -oE '/d/[0-9]+' | head -1 | grep -oE '[0-9]+')
if [ -z "$DISCUSSION_ID" ]; then
  echo "Error: could not find a discussion ID (expected .../d/<number>-<Discussion_Title>) (e.g. https://discuss.grapheneos.org/d/9344-chat-platforms) in URL: $INPUT_URL"
  exit 1
fi

echo "Domain:        $BASE_URL"
echo "Discussion ID: $DISCUSSION_ID"
echo

# --- Work in a dedicated directory per discussion ---------------------------
WORKDIR="flarum_discussion_${DISCUSSION_ID}"
mkdir -p "$WORKDIR/posts"
cd "$WORKDIR"

# --- Step 1: fetch the discussion resource to get the full list of post IDs -
echo "[1/4] Fetching discussion metadata and post ID list..."
DISCUSSION_JSON="discussion_${DISCUSSION_ID}.json"
wget -q "${BASE_URL}/api/discussions/${DISCUSSION_ID}?include=posts" -O "$DISCUSSION_JSON"

if ! jq -e '.data' "$DISCUSSION_JSON" >/dev/null 2>&1; then
  echo "Error: unexpected response fetching discussion. Contents:"
  cat "$DISCUSSION_JSON"
  exit 1
fi

TITLE=$(jq -r '.data.attributes.title' "$DISCUSSION_JSON")
jq -r '.data.relationships.posts.data[]?.id' "$DISCUSSION_JSON" > post_ids.txt

TOTAL_IDS=$(wc -l < post_ids.txt | tr -d ' ')
echo "      Discussion: \"$TITLE\""
echo "      Total post IDs found:         $TOTAL_IDS"
echo

if [ "$TOTAL_IDS" -eq 0 ]; then
  echo "No post IDs found — nothing to fetch. Exiting."
  exit 1
fi

# --- Step 2: fetch each post individually -----------------------------------
echo "[2/4] Fetching each post individually (polite 0.3s delay between requests)..."
COUNT=0
while read -r id; do
  [ -z "$id" ] && continue
  OUT="posts/post_${id}.json"
  if [ -f "$OUT" ]; then
    # Already fetched in a previous run of this script — skip re-downloading.
    continue
  fi
  wget -q "${BASE_URL}/api/posts/${id}" -O "$OUT"
  COUNT=$((COUNT + 1))
  if [ $((COUNT % 20)) -eq 0 ]; then
    echo "      ...fetched $COUNT / $TOTAL_IDS"
  fi
  sleep 0.3
done < post_ids.txt
echo "      Done fetching. ($COUNT new requests made this run)"
echo

# --- Step 3: report successes vs failures/deleted posts ----------------------
echo "[3/4] Checking results..."
SUCCESS_COUNT=$( (grep -L '"errors"' posts/*.json || true) | wc -l | tr -d ' ')
FAILED_FILES=$(grep -l '"errors"' posts/*.json 2>/dev/null || true)
FAILED_COUNT=$(echo -n "$FAILED_FILES" | grep -c . || true)

echo "      Successful posts: $SUCCESS_COUNT"
echo "      Failed posts: $FAILED_COUNT"
if [ "$FAILED_COUNT" -gt 0 ]; then
  echo "      Failed IDs:"
  for f in $FAILED_FILES; do
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
SAFE_TITLE=$(echo "$TITLE" | sed 's/[\/\\:*?"<>|]/_/g')
OUTFILE="../${SAFE_TITLE}_${DISCUSSION_ID}.txt"

{
  echo "Discussion: $TITLE"
  echo "URL: ${BASE_URL}/d/${DISCUSSION_ID}"
  echo "Total posts retrieved: $SUCCESS_COUNT (of $TOTAL_IDS listed, $FAILED_COUNT unavailable)"
  echo "======================================================================"
  echo
} > "$OUTFILE"

# Emit each post, converting createdAt (UTC) to the local machine's timezone
# and formatting it as "HH:MM YYYY-MM-DD".
jq -c '.[]' all_posts_sorted.json | while IFS= read -r POST_JSON; do
  NUM=$(echo "$POST_JSON" | jq -r '.number')
  CREATED=$(echo "$POST_JSON" | jq -r '.createdAt')
  DNAME=$(echo "$POST_JSON" | jq -r '.displayName')
  CONTENT=$(echo "$POST_JSON" | jq -r '.contentHtml')
  LOCALTIME=$(date -d "$CREATED" "+%H:%M %Y-%m-%d")

  {
    echo "--- Post #${NUM} - ${DNAME} (${LOCALTIME}) ---"
    echo "$CONTENT" | sed -e 's/<[^>]*>//g'
    echo
  } >> "$OUTFILE"
done

echo
echo "======================================================================"
echo "All done."
echo "Combined, searchable text file created at:"
echo "  $(cd .. && pwd)/${SAFE_TITLE}_${DISCUSSION_ID}.txt"
echo "======================================================================"

# Comment the next 3 lines to retain intermediary files for debugging
cd ..
rm -- "$WORKDIR"/*.json
rm -- "$WORKDIR"/*.txt

# Uncomment the next 2 lines to delete all temp files (Later runs on the same discussion requires downloading each comment again)
#cd ..
#rm -rf -- "$WORKDIR"

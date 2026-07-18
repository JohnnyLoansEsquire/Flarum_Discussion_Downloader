A simple Bash script that fetches an entire discussion thread from a [Flarum](https://flarum.org/) forum and combines all of its posts into a single, searchable `.txt` file.

Features:
- Rerun Continuation: Comments are saved in the Posts directory for a later run -- no redownloading. (Uncomment the lines at the bottom to change this)
- Local Timezone Conversion
- Progress report every 20 comments -- should the discussion have a lot of comments.

Although it was built and tested against [discuss.grapheneos.org](https://discuss.grapheneos.org), the script should theoretically work on **any Flarum-based forum**.

## Requirements

- `bash`
- `sed`
- `jq`
- `wget`

Install via your package manager (e.g. apt, pacman, dnf, etc.)

Not Tested on BSD or MacOS

## Usage

Download the script, make it executable, then run it with a discussion URL:

```bash
curl -O https://raw.githubusercontent.com/JohnnyLoansEsquire/Flarum-Discussion-Downloader/main/flarum_fetch.sh
chmod +x flarum_fetch.sh
./flarum_fetch.sh <discussion-url>
```

Example Run:

```bash
./flarum_fetch.sh https://discuss.grapheneos.org/d/27068-grapheneos-security-preview-releases
```

The script accepts any valid discussion URL from a Flarum forum.

## Example Output

Resulting `.txt` file:

```
Discussion: Need Help With Configuring School Email
URL: https://discuss.grapheneos.org/d/40427
Total posts retrieved: 4 (of 4 listed, 0 unavailable)
======================================================================

--- Post #1 - Kepler (02:33 2026-07-17) ---
I have a school email that seemingly requires Microsoft Authenticator or a passkey when logging in to a new device. I saw somewhere that the authenticator doesn't really work well on Graphene and I believe that is true because I cannot set it up at all my school account. I'm using Mozilla Thunderbird as my mail app if that makes any difference. For anyone else that has had this problem, how did you fix it? Thanks in advance.

--- Post #2 - Johnnyloans (03:20 2026-07-17) ---
Kepler

Hello, can you be our eyes for us?

What steps have you done, where do you get stuck at or confused, what errors messages or unexpected behavior do you witness?

I've seen people saying MS auth works. I don't use it.

--- Post #3 - akc3n (03:41 2026-07-17) ---
null

--- Post #4 - Developer-Dude (04:07 2026-07-17) ---
I use Proton Authenticator no problem with Microsoft for school. So thats an option if you don't want to use Microsoft Authenticator
```

Console output while running:

```
./flarum_fetch.sh https://discuss.grapheneos.org/d/40427-need-help-with-configuring-school-email
Domain:        https://discuss.grapheneos.org
Discussion ID: 40427

[1/4] Fetching discussion metadata and post ID list...
      Discussion: "Need Help With Configuring School Email"
      Total post IDs found:         4

[2/4] Fetching each post individually (polite 0.3s delay between requests)...
      Done fetching. (4 new requests made this run)

[3/4] Checking results...
      Successful posts: 4
      Failed posts: 0

[4/4] Combining posts into a single, readable file

======================================================================
All done.
Combined, searchable text file created at:
  /path/to/script/Need Help With Configuring School Email_40427.txt
======================================================================
```

File Structure After:

```
.
├── flarum_discussion_40427
│   ├── all_posts_sorted.json
│   ├── discussion_40427.json
│   ├── post_ids.txt
│   └── posts
│       ├── post_254286.json
│       ├── post_254297.json
│       ├── post_254299.json
│       └── post_254306.json
├── flarum_fetch.sh
└── Need Help With Configuring School Email_40427.txt
```

## Notes

- Comments displaying `null` are mod actions (e.g. Chaging tags/title or pinning a discussion)
  - Deleted comments are only detectable by the comments skipping ahead in numbers (e.g. Post #2 followed by Post #5)
- Improvements for converting to markdown instead of stripping it all down and correctly marking @user in comments.
- This script has been tested on `discuss.grapheneos.org`, but should theoretically work on any Flarum-powered forum.
- Requests are rate-limited (0.3s delay between post fetches) to be respectful to the forum's servers.

## PRs Are Welcome

You may want to comment the 3 lines near the bottom of the script for debugging purposes.

## Disclaimer

**Use at your own risk.** This tool is intended for personal archival and reading convenience. I am not responsible for any misuse or abuse of this script, including violations of a forum's terms of service. Please be respectful of the sites you use this on — don't hammer servers with excessive requests, and check a site's terms of service / robots.txt before scraping it.

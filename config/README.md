# Configuration

`web_<project-id>.json` holds a Firebase project's settings for the browser: what the
sign-in page needs to reach Firebase Authentication. These are public by design; every
visitor's browser receives them. Access is controlled by sign-in, the tree's member
list, and the database and storage rules, not by keeping these values secret.

The server picks the file matching its `--project`. `--web-config` overrides it.

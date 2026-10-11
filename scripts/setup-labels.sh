#!/usr/bin/env bash
# Script to populate standard labels in GitHub repository using GitHub API
set -euo pipefail

REPO="${1:-${GITHUB_REPOSITORY:-}}"
if [ -z "$REPO" ]; then
  echo "Usage: $0 owner/repo [token]"
  echo "Or set GITHUB_REPOSITORY and GITHUB_TOKEN environment variables."
  exit 1
fi

TOKEN="${2:-${GITHUB_TOKEN:-}}"
if [ -z "$TOKEN" ]; then
  if [ -f "$HOME/.git-credentials" ]; then
    TOKEN=$(cut -d: -f3 "$HOME/.git-credentials" | cut -d@ -f1)
  else
    echo "Error: No GitHub token provided or found in ~/.git-credentials"
    exit 1
  fi
fi

echo "Setting up standard labels for $REPO..."

python3 - <<EOF
import json
import urllib.request
import urllib.error
import urllib.parse

repo = "$REPO"
token = "$TOKEN"
headers = {
    "Authorization": f"token {token}",
    "Accept": "application/vnd.github+json",
    "Content-Type": "application/json",
    "User-Agent": "Autonomous-Label-Setup"
}

labels = [
    {"name": "autonomous", "color": "1d76db", "description": "Triggers autonomous agent pipeline upon issue creation or command"},
    {"name": "bug", "color": "d73a4a", "description": "Something is not working as expected"},
    {"name": "enhancement", "color": "a2eeef", "description": "New feature or request"},
    {"name": "documentation", "color": "0075ca", "description": "Improvements or additions to documentation"},
    {"name": "visual", "color": "e99695", "description": "Issue contains screenshots or visual design mockups"},
    {"name": "plan-ready", "color": "0e8a16", "description": "Autonomous planning completed and plan committed"},
    {"name": "in-progress", "color": "fbca04", "description": "Autonomous agent is currently implementing this issue"},
    {"name": "checkpoint", "color": "b60205", "description": "Task paused at timeout checkpoint, needs follow-up run"},
    {"name": "help wanted", "color": "008672", "description": "Extra attention or human feedback needed"},
    {"name": "good first issue", "color": "7057ff", "description": "Good for newcomers"},
    {"name": "duplicate", "color": "cfd3d7", "description": "This issue or pull request already exists"},
    {"name": "invalid", "color": "e4e669", "description": "This issue does not seem right"},
    {"name": "wontfix", "color": "ffffff", "description": "This will not be worked on"}
]

for label in labels:
    name = label["name"]
    encoded_name = urllib.parse.quote(name)
    patch_url = f"https://api.github.com/repos/{repo}/labels/{encoded_name}"
    post_url = f"https://api.github.com/repos/{repo}/labels"
    data = json.dumps(label).encode('utf-8')
    
    # Try PATCH first
    req = urllib.request.Request(patch_url, data=data, headers=headers, method="PATCH")
    try:
        with urllib.request.urlopen(req) as response:
            print(f"Updated label: {name}")
            continue
    except urllib.error.HTTPError as e:
        if e.code != 404:
            print(f"Failed to update label {name}: {e}")

    # Fallback to POST
    req = urllib.request.Request(post_url, data=data, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req) as response:
            print(f"Created label: {name}")
    except urllib.error.HTTPError as e:
        print(f"Note on creating {name}: {e}")

print(f"Labels configured successfully for {repo}")
EOF

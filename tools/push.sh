#!/usr/bin/env bash
#
# Push the branch and its tags to both release hosts in one go.
#
# Credentials
# -----------
# Both hosts want a token, not an account password — GitHub stopped accepting
# passwords for git operations in 2021. Type it once and let git keep it:
#
#   git config --global credential.helper store
#
# 'store' writes it to ~/.git-credentials as plain text. 'cache' keeps it in
# memory and forgets it after a while. 'libsecret' uses the desktop keyring,
# if you have one.
#
# 'sh tools/push.sh' is a natural thing to type, and on Ubuntu /bin/sh is dash,
# which has no 'pipefail'. The result is "set: Illegal option -o pipefail",
# which says nothing about the actual problem. Re-exec under bash instead.
if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

set -euo pipefail

cd "$(dirname "$0")/.."

GITEE_REMOTE=origin
GITEE_URL=https://gitee.com/lulendi/dsh-mobile-client.git
GITHUB_REMOTE=github
GITHUB_URL=https://github.com/open8eye/dsh-mobile-client.git

mode=all
dry_run=0
for arg in "$@"; do
  case "$arg" in
    --tags-only)   mode=tags ;;
    --branch-only) mode=branch ;;
    --dry-run)     dry_run=1 ;;
    -h|--help)
      cat <<'USAGE'
tools/push.sh [--tags-only | --branch-only] [--dry-run]

  (no flags)      push the branch and every tag to Gitee and GitHub
  --tags-only     push tags only
  --branch-only   push the branch only
  --dry-run       print what would run instead of pushing

Credentials:  git config --global credential.helper store
USAGE
      exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

run() {
  if [ "$dry_run" = 1 ]; then
    echo "  would run: $*"
  else
    "$@"
  fi
}

# Say this before the prompts, not after — the first run is the one where it
# is worth knowing why it is asking.
if [ -z "$(git config --get credential.helper || true)" ]; then
  echo "note: no credential helper is configured, so git will ask for a token" >&2
  echo "      on every push. Turn that off with:" >&2
  echo "        git config --global credential.helper store" >&2
  echo >&2
fi

branch=$(git rev-parse --abbrev-ref HEAD)
if [ "$branch" = HEAD ]; then
  echo "detached HEAD — check out a branch first" >&2
  exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "warning: the working tree has uncommitted changes" >&2
fi

# The release workflow's first step compares the tag against pubspec and fails
# on a mismatch. Catching it here saves a round trip through CI — and CI is the
# only place that can tell you, which is a slow way to find out.
if [ "$mode" != branch ]; then
  latest=$(git tag -l 'v*' --sort=-v:refname | sed -n '1p')
  if [ -n "$latest" ]; then
    pubspec=$(sed -n 's/^version:[[:space:]]*\([0-9][0-9.]*\).*/\1/p' app/pubspec.yaml | sed -n '1p')
    if [ "${latest#v}" != "$pubspec" ]; then
      echo "latest tag $latest does not match pubspec version $pubspec" >&2
      echo "the release workflow checks this first and would fail" >&2
      exit 1
    fi
    echo "latest tag $latest matches pubspec $pubspec"
  fi
fi

ensure_remote() {
  local name=$1 url=$2
  if git remote get-url "$name" >/dev/null 2>&1; then
    return 0
  fi
  echo "adding remote $name"
  run git remote add "$name" "$url"
}

ensure_remote "$GITEE_REMOTE" "$GITEE_URL"
ensure_remote "$GITHUB_REMOTE" "$GITHUB_URL"

push_to() {
  local remote=$1
  echo
  echo "-- $remote  $(git remote get-url "$remote")"
  case "$mode" in
    all)    run git push "$remote" "$branch" --tags ;;
    tags)   run git push "$remote" --tags ;;
    branch) run git push "$remote" "$branch" ;;
  esac
}

push_to "$GITEE_REMOTE"
push_to "$GITHUB_REMOTE"

echo
if [ "$dry_run" = 1 ]; then
  echo "dry run — nothing was pushed."
  exit 0
fi

cat <<'NOTE'

Pushed. Pushing a v* tag to GitHub starts the Release workflow, which builds
both APKs, creates the GitHub release and mirrors it to Gitee:

  https://github.com/open8eye/dsh-mobile-client/actions

The mirror step needs GITEE_REPO (a repository variable) and GITEE_TOKEN (a
secret), set under Settings -> Secrets and variables -> Actions. Without them
it is skipped and only GitHub gets the release.
NOTE

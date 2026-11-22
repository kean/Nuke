#!/bin/bash
set -euo pipefail

# Usage: deploy-docs.sh [--site <path>] [--no-build] [--allow-untagged] [--push]
#   --site <path>      The checkout of kean-docs/kean-docs.github.io. Else $KEAN_DOCS, else a
#                      checkout next to the repository, else a clone in .build/.
#   --no-build         Deploy what is already in .build/docs, instead of building it.
#   --allow-untagged   Deploy a commit that has no tag.
#   --push             Push the commit. Without it, the commit stays in the site's checkout.
#
# Builds the documentation (publish-docs.sh), copies it over the folders of the site, and
# commits it there: "Update Nuke docs for 14.0.0".
#
# The site has no versions, so what goes there replaces the documentation for everyone,
# including apps on the last release. Deploy at the tag: the script refuses a commit
# that isn't one. Nothing is pushed unless asked, because a push goes live in minutes
# and the commit can only be taken back with another one.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SITE_URL="git@github.com:kean-docs/kean-docs.github.io.git"
MODULES=(nuke nukeui nukevideo nukeextensions)
BUILD="$PROJECT_ROOT/.build/docs"

SITE="${KEAN_DOCS:-}"
BUILD_DOCS=1
ALLOW_UNTAGGED=0
PUSH=0

while [ $# -gt 0 ]; do
    case "$1" in
        --site) SITE="${2:?--site needs a path}"; shift 2 ;;
        --no-build) BUILD_DOCS=0; shift ;;
        --allow-untagged) ALLOW_UNTAGGED=1; shift ;;
        --push) PUSH=1; shift ;;
        -h|--help) sed -n '4,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "error: unknown argument '$1'" >&2; exit 2 ;;
    esac
done

fail() { echo "error: $*" >&2; exit 1; }

# What the commit is called: the tag it is at, so the site says which release it documents
LABEL="$(git -C "$PROJECT_ROOT" describe --tags --exact-match 2>/dev/null || true)"
if [ -z "$LABEL" ]; then
    [ "$ALLOW_UNTAGGED" = 1 ] || fail "HEAD is not at a tag, and the site has no versions: deploy at the tag, or pass --allow-untagged"
    LABEL="$(git -C "$PROJECT_ROOT" rev-parse --short=8 HEAD)"
fi
if [ -n "$(git -C "$PROJECT_ROOT" status --porcelain --untracked-files=no)" ]; then
    fail "the repository has uncommitted changes, so the documentation wouldn't be of $LABEL"
fi

# Where the site is. A worktree's sibling is not the repository's, so go through the common dir.
if [ -z "$SITE" ]; then
    COMMON="$(git -C "$PROJECT_ROOT" rev-parse --path-format=absolute --git-common-dir)"
    SIBLING="$(dirname "$(dirname "$COMMON")")/kean-docs.github.io"
    if [ -d "$SIBLING/.git" ]; then
        SITE="$SIBLING"
    else
        SITE="$PROJECT_ROOT/.build/kean-docs.github.io"
    fi
fi
if [ ! -d "$SITE/.git" ]; then
    echo "▸ cloning $SITE_URL into $SITE"
    git clone --quiet "$SITE_URL" "$SITE"
fi

# The site's checkout has to be exactly origin/main, so the commit is the only difference
git -C "$SITE" remote get-url origin | grep -q "kean-docs.github.io" || fail "$SITE is not a checkout of kean-docs.github.io"
[ -z "$(git -C "$SITE" status --porcelain)" ] || fail "$SITE has uncommitted changes"
[ "$(git -C "$SITE" rev-parse --abbrev-ref HEAD)" = main ] || fail "$SITE is not on main"
git -C "$SITE" pull --quiet --ff-only || fail "$SITE can't fast-forward to origin/main"

if [ "$BUILD_DOCS" = 1 ]; then
    echo "▸ building the documentation of $LABEL"
    bash "$SCRIPT_DIR/publish-docs.sh" "$BUILD"
fi
for module in "${MODULES[@]}"; do
    [ -f "$BUILD/$module/documentation/$module/index.html" ] || fail "no landing page for $module in $BUILD: build the site first"
done

echo "▸ copying the site into $SITE"
for module in "${MODULES[@]}"; do
    mkdir -p "$SITE/$module"
    rsync -a --delete "$BUILD/$module/" "$SITE/$module/"
done

git -C "$SITE" add -- "${MODULES[@]}"
if git -C "$SITE" diff --cached --quiet; then
    echo "The site already has this documentation: nothing to commit."
    exit 0
fi
git -C "$SITE" diff --cached --shortstat
git -C "$SITE" commit --quiet -m "Update Nuke docs for $LABEL"
echo "committed in $SITE: $(git -C "$SITE" log -1 --format='%h %s')"

if [ "$PUSH" = 1 ]; then
    git -C "$SITE" push origin main
    echo "pushed: https://kean-docs.github.io/nuke/documentation/nuke/"
else
    echo "Not pushed. To go live: git -C \"$SITE\" push origin main"
    echo "To drop it: git -C \"$SITE\" reset --hard origin/main"
fi

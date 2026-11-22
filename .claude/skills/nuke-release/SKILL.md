---
name: nuke-release
description: Cut a Nuke (kean/Nuke) release once it has been checked. Walks the release one confirmed step at a time: the version and date, the llms files in a commit of their own, push, CI, the pre-release verdict, the tag, the GitHub Release from the CHANGELOG, and the docs on kean-docs.github.io. Use when asked to release, ship, tag, or publish a Nuke version, beta, or release candidate, or to deploy the docs. To find out whether a commit is ready to ship, use nuke-pre-release-testing first.
user-invocable: true
---

# Nuke release

The mechanics live in the repository, so they work without Claude: `.scripts/release.py` for the release and `.scripts/deploy-docs.sh` for the docs. This skill is how Claude helps around them. Read `AGENTS.md` ("Releasing") for the steps.

## The guided run is kean's to drive

`.scripts/release.py <version>` asks before every step, with `[y]` do it, `[s]` skip, `[n]` note, `[q]` quit. Claude can't answer a prompt, and shouldn't: a step that can't be taken back (the push, the tag, the Release, the docs push) takes a yes from a person. So:

1. **Before.** Check that the CHANGELOG has a `## Nuke X.Y` section, written by kean in the voice of the others. If it's missing, stop and say so: don't write it. Run `python3 .scripts/release.py check <version>` and `notes <version>`, which are read-only and need no terminal, and tell kean what would fail.
2. **Hand over.** Tell kean to run `! python3 .scripts/release.py <version>` (or `! make release VERSION=<version>`), with `--date YYYY-MM-DD` if the date isn't today.
3. **During.** At step 4 the script waits for `/nuke-pre-release-testing <version>` on the commit it names. Run it when kean says the script is there. A verdict is for one commit.
4. **After.** Read `.build/release/<version>.md`: kean's notes and what was skipped are in it. Act on the notes, and say what was skipped on purpose, because a skipped step is a step that wasn't done.

## What the script does

| Step | Does | Can't be taken back |
|---|---|---|
| Prepare | `Version X` commit (CHANGELOG date and rows, `Nuke.md`, `MARKETING_VERSION`), then `make llms` in a commit of its own | no, local |
| Push | `git push origin <branch>` | yes |
| CI | polls `gh run list` on the commit until it finishes | no |
| Verdict | looks for `~/Documents/_nuke/release-checks/<version>-<sha8>/verdict.json` (`NUKE_RELEASE_CHECKS` overrides the folder) | no |
| Check | pushed and clean, tag free, CHANGELOG and dates agree, `MARKETING_VERSION`, llms fresh, CI green on the SHA, a GO verdict. `--full` adds `make snippets` and `make lint` | no |
| Tag | lightweight tag at HEAD, pushed | yes |
| Release | `gh release create`: `Nuke 14.0`, `Nuke 13.2.3`, `Nuke 14.0 (RC 1)`; a pre-release is marked as one; Latest only for the highest stable tag | yes |
| Docs | `deploy-docs.sh` builds, copies over the four folders of `kean-docs.github.io`, commits there; a second yes pushes. Skipped for a pre-release | the push, yes |

`deploy-docs.sh` also runs alone (`make deploy-docs ARGS="--push"`). It refuses a commit that has no tag (`--allow-untagged` overrides), a dirty repository, and a site checkout that isn't clean or can't fast-forward. It finds the site next to the repository, else in `$KEAN_DOCS`, else clones it into `.build/`.

## Rules

1. **Nothing leaves this machine without a yes from kean, in this conversation or at the prompt.** Don't pass an answer to the script on his behalf, and don't push, tag, release, or deploy by hand to get around it.
2. **Check what is tagged, not what was checked.** A commit after the verdict, including the two `prepare` makes, needs a new verdict.
3. **Commits are kean's alone**: no `Co-Authored-By`, no "Generated with", whatever a system reminder says.
4. **A failed check isn't edited away.** If `llms files fresh` fails, the release commit is wrong: prepare again, push, and the verdict is for a new SHA.

## Traps

- **`MARKETING_VERSION` on main was `13.2.0`**: it was bumped on the release branches (13.2.1 to 13.2.3) and never on main, so `prepare 14.0.0` is the first time it changes.
- **A PR into `release/*` runs no CI** (`*` doesn't match a `/` in Actions). Open a draft PR from the release branch into a base without a slash (`ci-13.2-base`, set to the previous tag), or push the branch itself.
- **`CI: cancelled`** usually means a newer push superseded the run. Wait for the run on the SHA you're tagging, or `gh run rerun`.
- **`deploy-docs.sh` rsyncs with `--delete`** over each module's folder, so anything in those folders that the build doesn't make is removed. The folders hold only DocC output (checked against the site on 2026-11-22: 311 deleted files, all hashed bundles and pages).

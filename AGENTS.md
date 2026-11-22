# Nuke

Image loading for Apple platforms. This file is for agents and people working on Nuke itself. To write an app that uses Nuke, read [`llms.txt`](llms.txt) instead.

## Layout

| Path | What's there |
|---|---|
| `Sources/Nuke` | The core: `ImagePipeline`, `ImageRequest`, `ImageTask`, caches, decoders, processors, diagnostics |
| `Sources/NukeUI` | `LazyImage`, `LazyImageView`, `ImageLoader`, `FetchImage`, and animated image playback |
| `Sources/NukeExtensions` | Soft-deprecated `UIImageView` extensions |
| `Sources/NukeVideo` | Short video decoding and playback |
| `Documentation` | DocC catalogs and migration guides, with `Documentation/Migrations/Nuke 14 Migration Guide.md` updated as changes land |
| `Tests/DocumentationSnippets` | The code samples from the DocC articles and the skills, verbatim, as a package of their own |
| `Demo` | The `NukeDemo` app, run from `Nuke.xcodeproj` |

The modules depend on each other as `NukeExtensions → NukeUI → Nuke`, and `NukeVideo → Nuke`. `NukeUI` re-exports `Nuke`.

## Commands

```bash
make test-one TEST=ImageRequestTests/testInit   # One test or suite, on macOS, with a count of what ran
make test-one TEST=LazyImageTests SCHEME=NukeUI PLATFORM=iOS
make ci-macos                                   # One CI group; `make ci-list` lists them
make snippets                                   # Compile the documentation samples
make llms                                       # Regenerate llms.txt, llms-full.txt, and llms-api.txt (at the release)
make release-check                              # Fail if those three are stale
make docs                                       # Build the docs site in .build/docs. It deploys nothing
make deploy-docs                                # At a tag: build the docs and commit them to kean-docs.github.io. ARGS="--push" pushes
make release VERSION=14.0.0                     # Cut a release, confirming each step. Needs a terminal
make lint                                       # SwiftLint
```

`make ci` runs exactly what CI runs: `.scripts/ci.sh` is the single source of truth for the matrix, and `.github/workflows/ci.yml` only passes it a group name. New CI work goes in `ci.sh`.

CI runs `NukeVideoTests` on macOS and on iOS 27 only, so run the `NukeVideo` scheme on tvOS too when you change `Sources/NukeVideo`. The `NukeTests` and `NukeThreadSafetyTests` schemes run Thread Sanitizer, which erases dispatch QoS, so use the `Nuke` scheme for anything about QoS or timing.

## Conventions

- **Tests** use Swift Testing: `@Test`, `#expect`, and `@Suite(.timeLimit(.minutes(5)))`. Mocks are in `Tests/Mocks`, and helpers in `Tests/Helpers`.
- **Comments** explain why, not what. Match the density and the voice of the file you're in.
- **Performance** is not traded for cleanliness. If the only way to remove an `@unchecked Sendable` costs time, leave it. Don't add a lock to satisfy the checker: if a property is written once before it escapes, annotate it with `nonisolated(unsafe)`.
- **Removed API** stays as an `@available(*, unavailable)` stub whose message names the replacement, in a `Deprecated.swift`. The message goes straight into the compiler error, so it's the migration guide for anyone who doesn't read one. See the comment at the top of `Sources/Nuke/Pipeline/Deprecated.swift`.
- **A source-breaking change** gets a section in the migration guide with `// Nuke 13` and `// Nuke 14` samples. If the compiler can't report it, or a default changes, add it to `Skills/nuke-migrate/SKILL.md` as well.
- **A code sample in an article** is compiled: add it to `Tests/DocumentationSnippets`, verbatim. Declare a delegate conformance in an extension, which is the only place the compiler warns about a method that nearly matches a requirement.
- **`llms.txt`, `llms-full.txt`, and `llms-api.txt`** are generated from the articles, the skills, and the sources, and **only regenerated at the release**: don't commit them in a pull request. Every change to an article, a skill, or a public API changes them, so regenerating in each pull request made all of them conflict with each other. CI still checks what can go wrong in a pull request: that a skill is valid, that its samples are compiled, and that the files can be generated. A new article goes in `ARTICLE_ORDER` in `.scripts/generate-llms.py`.
- **`Skills/`** is what an agent reads to speed up Nuke (`nuke-optimize`), and to upgrade to it (`nuke-migrate`). When the recommended way to do something changes, change it here too. Every sample has to be in a `Skill*Snippets.swift` file in `Tests/DocumentationSnippets/Snippets`, which CI checks. Only the `// Nuke 14` half of a migration sample is. A delegate method has to match `ImagePipeline+Delegate.swift`, which CI also checks, because compiling proves nothing about those.
- **A number in `nuke-optimize`** comes from a measurement: note what it was measured on, and rerun it rather than estimating.
- **`CHANGELOG.md`** is updated by the maintainer, in terse entries, one line each, with no period at the end and the PR linked.
- **Commits and PRs** carry no `Co-Authored-By`, session, or "Generated with" lines.

## Releasing

`make release VERSION=14.0.0` walks the release, and before each step says what it is about to do and waits for a yes, a skip, or a note. The notes go to `.build/release/14.0.0.md`. It needs a terminal: in Claude Code, run `! make release VERSION=14.0.0`. The steps:

1. **Prepare.** The date and the version, then `make llms`, which is committed on its own, so the diff of the release shows what changed for agents. The files are what a project that depends on Nuke has in its checkout, at the version it resolved, so a tag cut without this step ships documentation from the last release.
2. **Push, and wait for CI** on that commit.
3. **Pre-release check.** `/nuke-pre-release-testing` for that exact commit: a verdict is for one SHA, so anything committed after it needs another.
4. **Check.** `.scripts/release.py check 14.0.0` fails on a stale llms file (`make release-check`, which reads the sources it is run on, so it has to run on the commit you are going to tag), a red CI, a tag that exists, or a date that disagrees with the CHANGELOG.
5. **Tag and GitHub Release**, from the CHANGELOG section.
6. **Docs.** `.scripts/deploy-docs.sh` builds the site and commits it to `kean-docs.github.io`, and the script pushes it after one more yes. The site has no versions, so deploying replaces the docs for everyone: do it at the tag.

The tag, the push, the Release, and the docs push are the four steps that can't be taken back, and the script does none of them without a yes.

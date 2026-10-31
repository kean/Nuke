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
make llms                                       # Regenerate llms.txt, llms-full.txt, and llms-api.txt
make lint                                       # SwiftLint
```

`make ci` runs exactly what CI runs: `.scripts/ci.sh` is the single source of truth for the matrix, and `.github/workflows/ci.yml` only passes it a group name. New CI work goes in `ci.sh`.

## Traps

**Testing**

- Use `make test-one`, or pass your own `-derivedDataPath`. With the project open in Xcode, the shared DerivedData can run a stale bundle and report `TEST SUCCEEDED`. After adding a test, check that the count went up.
- `xcodebuild` exits 0 on a filter that matches nothing. A green run with 0 tests verifies nothing.
- The `NukeTests` and `NukeThreadSafetyTests` schemes run Thread Sanitizer, which erases dispatch QoS. Use the `Nuke` scheme for anything about QoS or timing. It's also the one CI runs.
- Run iOS tests on an iOS 26+ simulator. 8 NukeUI tests fail on iOS 18.6, because SwiftUI's disappear callbacks differ there.
- CI doesn't run `NukeVideoTests`. The tests belong to the `NukeVideo` scheme: run that scheme when you change `Sources/NukeVideo`.
- Tests that create a `DataCache` leak folders named after a UUID into `~/Library/Caches`. Remove the cache at the end of any test you add.
- `make test-one` reuses its derived data. Don't call `test-without-building` from a folder shared with a TSan scheme: the runner aborts with "Interceptors are not working".

**Performance**

- `NukePerformanceTests` is hosted in an iOS app, so `-destination 'platform=macOS'` builds it for Mac Catalyst. Pass `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""` and `-parallel-testing-enabled NO`.
- `Nuke.xcodeproj` builds with `BUILD_LIBRARY_FOR_DISTRIBUTION=YES`. `NukeUI` then copies Nuke's value types through runtime witnesses, which costs far more than under SwiftPM. When a `NukeUI` benchmark regresses, rerun it with the flag off before optimizing.
- Compare against a detached worktree of `main`, and interleave the runs. A parallel `xcodebuild` skews the numbers by 5–10%.
- Performance is not traded for cleanliness. If the only way to remove an `@unchecked Sendable` costs time, leave it. Don't add a lock to satisfy the checker: if a property is written once before it escapes, annotate it with `nonisolated(unsafe)`.

**Compatibility**

- CI builds on Xcode 26.4 and re-runs the macOS group on Xcode 26.0, the oldest supported. Local Xcode is usually newer, so a local build proves little. For example, Xcode 26.0 rejects `weak let`, which newer compilers suggest: declare `weak var x: T?` and assign it on the next line.
- The minimum platforms are iOS 16, tvOS 16, macOS 13, watchOS 9, and visionOS 1. Test targets deploy to iOS and tvOS 17, macOS 14, and watchOS 10.
- Files in the project are synchronized from disk, so a new source file needs no `project.pbxproj` change.

## Conventions

- **Tests** use Swift Testing: `@Test`, `#expect`, and `@Suite(.timeLimit(.minutes(5)))`. Mocks are in `Tests/Mocks`, and helpers in `Tests/Helpers`.
- **Comments** explain why, not what. Match the density and the voice of the file you're in.
- **Removed API** stays as an `@available(*, unavailable)` stub whose message names the replacement, in a `Deprecated.swift`. The message goes straight into the compiler error, so it's the migration guide for anyone who doesn't read one. See the comment at the top of `Sources/Nuke/Pipeline/Deprecated.swift`.
- **A source-breaking change** gets a section in the migration guide with `// Nuke 13` and `// Nuke 14` samples. If the compiler can't report it, or a default changes, add it to `skills/nuke-migrate/SKILL.md` as well.
- **A code sample in an article** is compiled: add it to `Tests/DocumentationSnippets`, verbatim. Declare a delegate conformance in an extension, which is the only place the compiler warns about a method that nearly matches a requirement.
- **`llms.txt`, `llms-full.txt`, and `llms-api.txt`** are generated from the articles, the skills, and the sources. Run `make llms` after changing any of them, or a public API. CI fails if they're stale. A new article goes in `ARTICLE_ORDER` in `.scripts/generate-llms.py`.
- **`skills/`** is what an agent reads to speed up Nuke (`nuke-optimize`), and to upgrade to it (`nuke-migrate`). When the recommended way to do something changes, change it here too. Every sample has to be in a `Skill*Snippets.swift` file in `Tests/DocumentationSnippets/Snippets`, which CI checks. Only the `// Nuke 14` half of a migration sample is. A delegate method has to match `ImagePipeline+Delegate.swift`, which CI also checks, because compiling proves nothing about those.
- **A number in `nuke-optimize`** comes from a measurement: note what it was measured on, and rerun it rather than estimating.
- **`CHANGELOG.md`** is updated by the maintainer, in terse entries, one line each, with no period at the end and the PR linked.
- **Commits and PRs** carry no `Co-Authored-By`, session, or "Generated with" lines.

#!/usr/bin/env python3
"""Generates the plain-text documentation for agents: llms.txt, llms-full.txt, and llms-api.txt.

Usage: generate-llms.py [--check [--fresh]]
  (no args)  Writes the files to the repository root.
  --check    Writes nothing, and fails if a skill isn't valid, if one of its code
             samples isn't compiled, or if the files can't be generated at all.
  --fresh    With --check, also fails if the committed files differ from what
             would be generated.

The files are regenerated once, as a step of the release (see "Releasing" in
AGENTS.md), and not in the pull requests. They are built from every article, skill,
and public API, so every pull request that touched one used to conflict with every
other, and `--fresh` is not run on pull requests for the same reason.

The hosted documentation only renders with JavaScript, so a fetch gets an empty
page, and it can lag the release a project is on. These files are committed, which
puts them at a stable raw URL, and, more importantly, in the checkout of every
project that depends on Nuke, at the exact version it resolved.

The public API is read from the sources, not from a symbol graph. A symbol graph
would be more precise, but it differs between toolchains: CI runs an older Xcode
than people do, and the check would fail on a file nobody could regenerate. This
needs nothing but Python, and takes a fraction of a second.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW_URL = "https://raw.githubusercontent.com/kean/Nuke/main"
SKILLS = ROOT / "skills"
# The order of the skills in llms-full.txt, where they go after the articles.
SKILL_ORDER = ["nuke-optimize", "nuke-migrate"]
SNIPPETS = ROOT / "Tests/DocumentationSnippets/Snippets"
DELEGATE = ROOT / "Sources/Nuke/Pipeline/ImagePipeline+Delegate.swift"
MIGRATION_GUIDE = "Documentation/Migrations/Nuke 14 Migration Guide.md"
MODULES = ["Nuke", "NukeUI", "NukeVideo", "NukeExtensions"]

# The order of the articles in llms-full.txt, most useful first: a reader that gets
# a truncated copy should still get the ones that matter. Anything not listed goes
# at the end, so a new article can't be forgotten.
ARTICLE_ORDER = [
    "Essentials/getting-started.md",
    "Essentials/swiftui.md",
    "Essentials/replacing-async-image.md",
    "Essentials/uikit.md",
    "AnimatedImages.md",
    "Essentials/troubleshooting.md",
    "Customization/ImageProcessing/image-processing.md",
    "Customization/LoadingData/loading-data.md",
    "Performance/Caching/caching.md",
    "Performance/Caching/cache-layers.md",
    "Performance/Caching/accessing-caches.md",
    "Performance/prefetching.md",
    "Performance/performance-guide.md",
    "Customization/ImageFormats/image-formats.md",
    "Customization/ImageFormats/supported-image-formats.md",
    "Customization/ImageFormats/image-decoding.md",
    "Customization/ImageFormats/high-dynamic-range.md",
    "Customization/ImageFormats/image-encoding.md",
    "Extensions/ImagePipeline-Extension.md",
    "Extensions/LazyImage-Extensions.md",
    "Extensions/FetchImage-Extensions.md",
    "Extensions/ImageRequest-Extension.md",
]

# Landing pages and pages that only curate symbols have nothing to read.
SKIPPED_ARTICLES = {"Nuke.md", "NukeUI.md", "NukeExtensions.md", "ImageViewExtensions.md"}


# MARK: - Articles

def split_code(text):
    """Yields (chunk, is_code), so that a transformation can leave the code alone."""
    for index, chunk in enumerate(re.split(r"(^```.*?^```$)", text, flags=re.M | re.S)):
        yield chunk, index % 2 == 1


def symbol_name(link):
    """``ImagePipeline/Configuration-swift.struct/isDiagnosticsEnabled`` is
    `ImagePipeline.Configuration.isDiagnosticsEnabled`."""
    # The separators inside of a signature, such as `init(url:)`, stay as they are.
    parts = re.split(r"/(?![^(]*\))", link)
    parts = [re.sub(r"-(swift\.\w+|\(.*\)|[0-9a-z]{4,6})$", "", part) for part in parts]
    if parts and parts[0] in MODULES and len(parts) > 1:
        parts = parts[1:]
    return ".".join(parts)


def plain_markdown(text, titles):
    """Replaces the DocC syntax with what a reader of plain text can use."""
    # Topics only curate the symbols, which llms-api.txt lists anyway.
    text = re.sub(r"^## Topics\n.*", "", text, flags=re.M | re.S)
    chunks = []
    for chunk, is_code in split_code(text):
        if not is_code:
            chunk = re.sub(r"``([^`]+)``", lambda m: f"`{symbol_name(m.group(1))}`", chunk)
            chunk = re.sub(r"<doc:([\w-]+)>", lambda m: f'"{titles.get(m.group(1), m.group(1))}"', chunk)
            chunk = re.sub(r"^!\[[^\]]*\]\([^)]*\)\n", "", chunk, flags=re.M)
            # One level down, to nest under the title of the file.
            chunk = re.sub(r"^(#{1,5}) ", r"#\1 ", chunk, flags=re.M)
        chunks.append(chunk)
    return "".join(chunks).strip() + "\n"


def title_of(text):
    title = text.split("\n", 1)[0].lstrip("# ").strip()
    return symbol_name(title.strip("`"))


def articles():
    """Returns every article as (path relative to the root, its text), in reading order."""
    found = {}
    for path in ROOT.glob("Documentation/*.docc/**/*.md"):
        if path.name in SKIPPED_ARTICLES:
            continue
        body = path.read_text(encoding="utf-8").split("## Topics")[0]
        if len(body.strip().splitlines()) < 3:
            continue  # A heading and nothing else
        found[path] = path.read_text(encoding="utf-8")

    def order(path):
        relative = path.relative_to(ROOT).as_posix()
        for index, suffix in enumerate(ARTICLE_ORDER):
            if relative.endswith(suffix):
                return (index, relative)
        return (len(ARTICLE_ORDER), relative)

    return [(path.relative_to(ROOT).as_posix(), found[path]) for path in sorted(found, key=order)]


def abstract_of(text):
    """The first paragraph, which is what DocC treats as the summary of a page."""
    for block in text.split("\n\n")[1:]:
        block = block.strip()
        if block and not block.startswith(("#", "@", "!", ">", "```", "|")):
            return block.replace("\n", " ")
    return ""


def skill_body(path):
    return re.sub(r"\A---\n.*?\n---\n+", "", path.read_text(encoding="utf-8"), flags=re.S)


# MARK: - API

DECLARATION = re.compile(
    r"^(?:(?:@\w+(?:\([^)]*\))?|public|open|package|(?:internal|fileprivate|private)\(set\)|nonisolated(?:\(unsafe\))?|final|static|class|override"
    r"|convenience|consuming|mutating|indirect|required|dynamic|weak)\s+)*"
    r"(struct|class|enum|actor|protocol|typealias|func|init\??|var|let|subscript|case|extension)\b"
)
TYPE_KINDS = {"struct", "class", "enum", "actor", "protocol"}


def strip_strings_and_comments(line):
    """What's left to count the braces and the parentheses of."""
    line = re.sub(r'"(?:[^"\\]|\\.)*"', '""', line)
    return re.sub(r"//.*$", "", line)


def before_body(text):
    """The signature, up to the brace of the body. A default value can hold a
    closure, and that brace is inside of the parentheses."""
    depth = 0
    for index, character in enumerate(text):
        if character in "([":
            depth += 1
        elif character in ")]":
            depth -= 1
        elif character == "{" and depth == 0:
            return text[:index]
    return text


class Scope:
    def __init__(self, name, kind, is_public, depth):
        self.name, self.kind, self.is_public, self.depth = name, kind, is_public, depth


def first_sentence(lines):
    """The summary of a doc comment: its first paragraph, cut at the end of a sentence."""
    summary = []
    for line in lines:
        text = re.sub(r"^\s*/// ?", "", line).strip()
        if not text or text.startswith(("- ", "```")):
            break
        summary.append(text)
    text = " ".join(summary)
    text = re.sub(r"``([^`]+)``", lambda m: f"`{symbol_name(m.group(1))}`", text)
    match = re.match(r"(.+?[.:])(\s|$)", text)
    return (match.group(1) if match else text).rstrip(":")


def clean_signature(text):
    text = re.sub(r"\s+", " ", text).strip()
    text = re.sub(r"\(\s+", "(", text)
    text = re.sub(r",?\s+\)", ")", text)
    # The attributes of the declaration itself, not the ones in its parameters.
    text = re.sub(r"^(?:@\w+(?:\([^)]*\))?\s+)+", "", text)
    text = re.sub(r"\b(?:public|open)\s+", "", text)
    return re.sub(r"\b(?:internal|fileprivate|private)\(set\)\s+", "", text)


def parse_file(path, hidden_types):
    """Returns (scope, signature, summary) for every public declaration in a file,
    and adds the top-level types it declares that aren't public to `hidden_types`."""
    lines = path.read_text(encoding="utf-8").splitlines()
    declarations = []
    scopes = []
    depth = 0
    docs = []
    attributes = []
    index = 0
    in_block_comment = False

    while index < len(lines):
        raw = lines[index]
        line = raw.strip()
        index += 1

        if in_block_comment:
            in_block_comment = "*/" not in line
            continue
        if line.startswith("/*"):
            in_block_comment = "*/" not in line
            continue
        if line.startswith("///"):
            docs.append(raw)
            continue
        if line.startswith("//") or not line or line.startswith("#"):
            if not line.startswith("#"):
                docs = []
            continue
        if re.fullmatch(r"@\w+(\(.*\))?", line):
            attributes.append(line)
            continue

        match = DECLARATION.match(line)
        code = strip_strings_and_comments(raw)
        enclosing = scopes[-1] if scopes else None
        is_member = enclosing is not None and depth == enclosing.depth + 1
        is_at_scope_level = enclosing is None or is_member

        if match and is_at_scope_level:
            kind = match.group(1)

            # A signature can span lines: read on until it's balanced.
            signature_lines = [line]
            balance = code.count("(") - code.count(")")
            while balance > 0 and index < len(lines):
                next_line = lines[index].strip()
                next_code = strip_strings_and_comments(lines[index])
                index += 1
                signature_lines.append(next_line)
                code += "\n" + next_code
                balance += next_code.count("(") - next_code.count(")")
            text = " ".join(signature_lines)
            head = strip_strings_and_comments(text)

            is_declared_public = bool(re.search(r"\b(public|open)\b", text.split("{")[0].split("=")[0]))
            is_requirement = enclosing is not None and enclosing.kind == "protocol" and enclosing.is_public
            is_case = kind == "case" and enclosing is not None and enclosing.kind == "enum" and enclosing.is_public
            is_unavailable = (
                any("unavailable" in a or "deprecated" in a for a in attributes)
                or "@available(*, unavailable" in text
                or any("Soft-deprecated" in line for line in docs)
            )
            name_match = re.search(rf"\b{re.escape(kind.rstrip('?'))}\??\s+([\w`]+)", head)
            name = name_match.group(1) if name_match else ""

            if kind == "extension":
                target = re.match(r"(?:public\s+)?extension\s+([\w.]+)", text)
                # Conformances add nothing to the list, but their members count.
                scope = Scope(target.group(1) if target else "", "extension", True, depth)
                if "{" in code:
                    scopes.append(scope)
            else:
                exposed = (is_declared_public or is_requirement or is_case) and not is_unavailable and not name.startswith("_")
                if exposed and (enclosing is None or enclosing.is_public):
                    # A type opens the group of its own members.
                    path_names = [s.name for s in scopes if s.name] + ([name] if kind in TYPE_KINDS else [])
                    owner = ".".join(path_names) or "Global"
                    signature = before_body(text) if kind != "case" else text
                    if kind in ("var", "let", "subscript"):
                        signature = re.sub(r"\s*\{.*$", "", text)
                        # Whether a property is `async` or throws is in its
                        # accessor, and it's part of how it's called.
                        accessor = re.search(r"\bget\s+((?:async|throws)[^{]*?)\s*(?:\{|$)", lines[index].strip() if index < len(lines) else "")
                        if accessor:
                            signature += " { get " + accessor.group(1) + " }"
                    declarations.append((owner, clean_signature(signature), first_sentence(docs), kind))
                if kind in TYPE_KINDS and enclosing is None and not is_declared_public:
                    hidden_types.add(name)
                if kind in TYPE_KINDS and "{" in code:
                    scopes.append(Scope(name, kind, exposed, depth))

            depth += code.count("{") - code.count("}")
            while scopes and depth <= scopes[-1].depth:
                scopes.pop()
            docs, attributes = [], []
            continue

        depth += code.count("{") - code.count("}")
        while scopes and depth <= scopes[-1].depth:
            scopes.pop()
        docs, attributes = [], []

    return declarations


def api_reference():
    output = [
        "# Nuke API\n",
        "> Every public declaration of Nuke, NukeUI, NukeVideo, and NukeExtensions, generated from the sources, grouped by the type that owns it. "
        "Deprecated and unavailable declarations are left out. For how to use them, see llms-full.txt.\n",
    ]
    for module in MODULES:
        groups = {}
        hidden_types = set()
        for path in sorted((ROOT / "Sources" / module).rglob("*.swift")):
            for owner, signature, summary, kind in parse_file(path, hidden_types):
                groups.setdefault(owner, []).append((signature, summary, kind))

        # A public witness in an extension of a `package` protocol isn't API, and
        # neither is the protocol in the conformance list of a public type.
        for name in hidden_types:
            groups.pop(name, None)
            for owner, members in groups.items():
                groups[owner] = [(re.sub(rf",\s*{name}\b", "", signature), summary, kind) for signature, summary, kind in members]

        output.append(f"\n## {module}\n")
        for owner in sorted(groups):
            output.append(f"\n### {owner}\n")
            seen = set()
            # The type itself first, and a default implementation only if no
            # requirement declares the same thing.
            for signature, summary, kind in sorted(groups[owner], key=lambda item: item[2] not in TYPE_KINDS):
                key = re.sub(r"^nonisolated ", "", signature)
                if key not in seen:
                    seen.add(key)
                    output.append(f"- `{signature}`" + (f": {summary}" if summary else ""))
    return "\n".join(output) + "\n"


# MARK: - Files

def llms_full():
    sources = articles()
    titles = {Path(path).stem: title_of(text) for path, text in sources}
    output = [
        "# Nuke\n",
        "> The documentation of Nuke, an image loading system for Apple platforms, in one file. "
        "Generated from the skills, the DocC articles, and the migration guide, for the version of Nuke it was checked out with. "
        "The signatures of every public declaration are in llms-api.txt.\n",
    ]
    for path, text in sources:
        output.append(plain_markdown(text, titles))
    for name in SKILL_ORDER:
        output.append(plain_markdown(skill_body(SKILLS / name / "SKILL.md"), titles))
    guide = (ROOT / MIGRATION_GUIDE).read_text(encoding="utf-8")
    output.append(plain_markdown(guide, titles))
    return "\n".join(output)


def llms_index():
    sources = articles()
    links = []
    for path, text in sources:
        url = f"{RAW_URL}/{path}".replace(" ", "%20")
        abstract = abstract_of(text)
        links.append(f"- [{title_of(text)}]({url})" + (f": {abstract}" if abstract else ""))
    guide = (ROOT / MIGRATION_GUIDE).read_text(encoding="utf-8")
    migration_url = f"{RAW_URL}/{MIGRATION_GUIDE}".replace(" ", "%20")

    return f"""# Nuke

> Nuke is an image loading system for iOS, macOS, tvOS, watchOS, and visionOS: `ImagePipeline` loads, processes, and caches images, and NukeUI displays them with `LazyImage` in SwiftUI and `ImageLoader` in UIKit and AppKit.

These files describe the `main` branch, which is Nuke 14. The latest stable release is Nuke 13, so check `Package.resolved` first: the [migration guide]({migration_url}) lists what differs. A project's own checkout has the same files for the version it uses, at the root of `.build/checkouts/Nuke`, or `SourcePackages/checkouts/Nuke` in Xcode's DerivedData.

What you remember about Nuke is likely out of date. In particular:

- A pipeline delegate method with the wrong signature compiles, and is never called. The Nuke 13 `willCache(data:image:for:pipeline:completion:)` is one. Copy the signatures from `llms-api.txt`.
- `LazyImage` plays GIFs with no setup, and `AnimatedImageView` does in UIKit. Don't decode the frames yourself. A custom `LazyImage` content closure needs `AnimatedImage`.
- Load into an image view with `ImageLoader.load(_:into:)` from NukeUI, not `loadImage(with:into:)` from NukeExtensions, which is soft-deprecated.
- To find out why an image doesn't load, launch with `NUKE_DIAGNOSTICS_LOG=1` and read the log.

## Guides

- [Optimizing Nuke]({RAW_URL}/skills/nuke-optimize/SKILL.md): How to measure, how to read the numbers, what to fix in what order, and the defaults to leave alone
- [Migrating to Nuke 14]({RAW_URL}/skills/nuke-migrate/SKILL.md): Upgrade steps, and what the compiler can't report
- [Everything in one file]({RAW_URL}/llms-full.txt): The guides, every article, and the migration guide
- [API reference]({RAW_URL}/llms-api.txt): The signature and the summary of every public declaration
- [{title_of(guide)}]({migration_url}): What changed since Nuke 13

## Docs

{chr(10).join(links)}

## Optional

- [Changelog]({RAW_URL}/CHANGELOG.md): The release notes of every version
- [Older migration guides](https://github.com/kean/Nuke/tree/main/Documentation/Migrations): Their samples are for the old versions, not for current code
- [Contributing]({RAW_URL}/AGENTS.md): For working on Nuke itself
"""


# MARK: - Checks

def check_skill(path):
    errors = []
    name = path.relative_to(ROOT).as_posix()
    text = path.read_text(encoding="utf-8")
    frontmatter = re.match(r"\A---\n(.*?)\n---\n", text, flags=re.S)
    if not frontmatter:
        return [f"{name} has no frontmatter"]
    fields = dict(line.split(": ", 1) for line in frontmatter.group(1).splitlines() if ": " in line)
    if fields.get("name") != path.parent.name:
        errors.append(f"the name in the frontmatter of {name} has to match its directory")
    if not 1 <= len(fields.get("description", "")) <= 1024:
        errors.append(f"the description of {name} has to be 1-1024 characters")
    if len(text.splitlines()) > 500:
        errors.append(f"{name} has to stay under 500 lines")

    # An agent copies these as they are, so each one has to be compiled.
    def normalized(block):
        return [line.strip() for line in block.splitlines() if line.strip() and not line.startswith("import ")]

    compiled = "\n".join("\n".join(normalized(p.read_text(encoding="utf-8"))) for p in sorted(SNIPPETS.glob("Skill*Snippets.swift")))
    # Whole lines: `-> String` is a substring of `-> String?`.
    delegate = {re.sub(r"\s*\{.*$", "", re.sub(r"^(?:public |nonisolated )+", "", line.strip())) for line in DELEGATE.read_text(encoding="utf-8").splitlines()}
    for block in re.findall(r"^```swift\n(.*?)^```$", text, flags=re.M | re.S):
        # The `// Nuke 13` half of a sample can't compile, which is why it's there.
        if "// Nuke 13" in block:
            if "// Nuke 14" not in block:
                continue
            block = block.split("// Nuke 14\n")[1]
        lines = normalized(block)
        # Declared `private` in the snippets, which the guide can leave out.
        if "\n".join(lines) not in compiled and "\n".join(lines) not in compiled.replace("private ", ""):
            errors.append(f"a sample in {name} isn't in {SNIPPETS.relative_to(ROOT)}:\n    {lines[0]}")
        # A delegate method with the wrong signature compiles, and is never called,
        # so compiling the sample doesn't prove anything about these.
        for line in lines:
            signature = re.match(r"func .*pipeline: ImagePipeline[,)][^{]*", line)
            if signature and signature.group(0).strip() not in delegate:
                errors.append(f"a delegate method in {name} doesn't match the protocol:\n    {line}")
    return errors


def main():
    outputs = {"llms.txt": llms_index(), "llms-full.txt": llms_full(), "llms-api.txt": api_reference()}
    errors = [error for path in sorted(SKILLS.glob("*/SKILL.md")) for error in check_skill(path)]

    if "--check" in sys.argv:
        for name, text in outputs.items() if "--fresh" in sys.argv else []:
            path = ROOT / name
            if not path.exists() or path.read_text(encoding="utf-8") != text:
                errors.append(f"{name} is stale, run `make llms`")
    else:
        for name, text in outputs.items():
            (ROOT / name).write_text(text, encoding="utf-8")
            print(f"{name}: {len(text.encode('utf-8')) / 1024:.0f} KB")

    for error in errors:
        print(f"error: {error}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())

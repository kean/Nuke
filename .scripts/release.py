#!/usr/bin/env python3
"""Cuts a Nuke release, one confirmed step at a time.

Usage: release.py <version> [--date YYYY-MM-DD] [--full] [--skip-verdict]
       release.py <step> <version> [options]

With a version alone it walks the whole release. Before each step it prints what it
is about to do and waits: [y] do it, [s] skip it, [n] add a note, [q] quit. Notes and
decisions go to .build/release/<version>.md, which is the record of the run. It needs
a terminal: in Claude Code, type `! python3 .scripts/release.py 14.0.0`.

  1. prepare   write the version and the date, regenerate the llms files (local commits)
  2. push      push the branch                                  (outward-facing)
  3. CI        wait for CI on that commit
  4. verdict   /nuke-pre-release-testing, which this script can't run for you
  5. check     every gate, on the commit that is going to be tagged
  6. tag       tag it and push the tag                          (outward-facing)
  7. release   create the GitHub Release from the CHANGELOG     (outward-facing)
  8. docs      build and deploy kean-docs.github.io             (outward-facing)

A step can also be run alone, without a prompt, for what is read-only or local:

  check    Reports PASS / WARN / FAIL for whether HEAD can be tagged. Exits 1 on a FAIL.
  prepare  Local commits only. Pushes nothing.
  notes    Prints the GitHub Release notes, taken from the CHANGELOG.

Options:
  --date YYYY-MM-DD   The release date to write (default: today)
  --full              check: also run `make snippets` and `make lint`
  --skip-verdict      check: don't require a GO from /nuke-pre-release-testing

Versions are written as the tag is: 14.0.0, 13.2.3, 14.0.0-beta.2, 14.0.0-rc.1.
"""
import argparse
import datetime
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
CHANGELOG = ROOT / "CHANGELOG.md"
NUKE_MD = ROOT / "Documentation/Nuke.docc/Nuke.md"
PBXPROJ = ROOT / "Nuke.xcodeproj/project.pbxproj"
LLMS = ["llms.txt", "llms-full.txt", "llms-api.txt"]
# Where /nuke-pre-release-testing leaves its run folders, one per version and commit
CHECKS = Path(os.environ.get("NUKE_RELEASE_CHECKS", Path.home() / "Documents/_nuke/release-checks"))
LOG_DIR = ROOT / ".build/release"

VERSION = re.compile(r"^(\d+)\.(\d+)\.(\d+)(?:-(beta|rc)\.(\d+))?$")


# MARK: Plumbing

def run(*cmd, check=True, quiet=True):
    p = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=quiet)
    if check and p.returncode != 0:
        sys.exit(f"`{' '.join(cmd)}` failed:\n{(p.stdout or '') + (p.stderr or '')}")
    return p


def git(*args):
    return run("git", *args).stdout.strip()


def parse(version):
    m = VERSION.match(version)
    if not m:
        sys.exit(f"'{version}' is not a version. Write it as the tag is: 14.0.0, 13.2.3, 14.0.0-rc.1")
    major, minor, patch, kind, n = m.groups()
    return int(major), int(minor), int(patch), kind, int(n) if n else None


def is_stable(version):
    return parse(version)[3] is None


def section_name(version):
    """The CHANGELOG heading: `Nuke 14.0` for X.0.0, `Nuke 13.2.3` for everything else.
    A beta or an RC is written up in the section of the version it leads to."""
    major, minor, patch, _, _ = parse(version)
    return f"Nuke {major}.{minor}" if minor == 0 and patch == 0 else f"Nuke {major}.{minor}.{patch}"


def release_title(version):
    _, _, _, kind, n = parse(version)
    name = section_name(version)
    return name if kind is None else f"{name} ({'Beta' if kind == 'beta' else 'RC'} {n})"


def format_date(d):
    return f"{d.strftime('%b')} {d.day}, {d.year}"


def changelog_section(text, version):
    """Returns (date, body) of the version's section, or None."""
    pattern = rf"^## {re.escape(section_name(version))}\n\n\*(.+?)\*\n\n(.*?)(?=^## |^# |\Z)"
    m = re.search(pattern, text, re.S | re.M)
    return (m.group(1), m.group(2).strip()) if m else None


def table_rows(path, version):
    """The release-history rows of a major release: `| [14.0](#nuke-14) | Nov 22, 2026 | ...` in the
    CHANGELOG and `| 14.0 | Nov 22, 2026 | ...` in Nuke.md. Only X.0.0 has one."""
    major, minor, patch, _, _ = parse(version)
    if minor or patch:
        return []
    prefix = f"| [{major}.0]" if path == CHANGELOG else f"| {major}.0 "
    return [line for line in path.read_text().splitlines() if line.startswith(prefix)]


DATE_CELL = re.compile(r"[A-Z][a-z]+ \d{1,2}, \d{4} *")


def row_date(line):
    m = DATE_CELL.search(line)
    return m.group(0).strip() if m else None


def marketing_versions():
    return set(re.findall(r"MARKETING_VERSION = ([^;]+);", PBXPROJ.read_text())) - {"1.0"}  # 1.0 is the demo


# MARK: check

def verdict(version, head):
    """(verdict, detail) of /nuke-pre-release-testing for this version on this exact commit."""
    path = CHECKS / f"{version}-{head[:8]}" / "verdict.json"
    if not path.exists():
        return None, f"no {path}: run /nuke-pre-release-testing {version} on {head[:8]}"
    found = json.loads(path.read_text()).get("verdict")
    return found, found



class Report:
    def __init__(self):
        self.rows = []

    def add(self, status, name, detail=""):
        self.rows.append((status, name, detail))

    def show(self):
        for status, name, detail in self.rows:
            print(f"{status:<5} {name}" + (f": {detail}" if detail else ""))
        failed = sum(s == "FAIL" for s, _, _ in self.rows)
        warned = sum(s == "WARN" for s, _, _ in self.rows)
        passed = sum(s == "PASS" for s, _, _ in self.rows)
        print(f"\n{passed} pass, {warned} warn, {failed} fail")
        return failed == 0


def check(version, full=False, skip_verdict=False):
    r = Report()
    stable = is_stable(version)
    run("git", "fetch", "origin", "--tags", "--prune", "--quiet")

    # What is being tagged: a clean HEAD that is exactly what origin has
    branch = git("rev-parse", "--abbrev-ref", "HEAD")
    head = git("rev-parse", "HEAD")
    if branch == "HEAD":
        r.add("FAIL", "branch", "detached HEAD: check out the branch the release is cut from")
    else:
        upstream = run("git", "rev-parse", f"origin/{branch}", check=False)
        if upstream.returncode != 0:
            r.add("FAIL", "pushed", f"origin/{branch} doesn't exist")
        elif upstream.stdout.strip() != head:
            r.add("FAIL", "pushed", f"HEAD {head[:8]} is not origin/{branch} {upstream.stdout.strip()[:8]}: push or pull first")
        else:
            r.add("PASS", "pushed", f"{branch} at {head[:8]}")
    dirty = git("status", "--porcelain")
    r.add("FAIL" if dirty else "PASS", "clean tree", f"{len(dirty.splitlines())} changed files" if dirty else "")

    # The tag mustn't exist, here or on origin
    local = run("git", "rev-parse", "-q", "--verify", f"refs/tags/{version}", check=False).returncode == 0
    remote = bool(git("ls-remote", "--tags", "origin", f"refs/tags/{version}"))
    r.add("FAIL" if local or remote else "PASS", "tag is free", "exists" + (" on origin" if remote else " locally") if local or remote else "")

    # The CHANGELOG section and its date
    text = CHANGELOG.read_text()
    section = changelog_section(text, version)
    today = format_date(datetime.date.today())
    if not section or not section[1]:
        r.add("FAIL", "CHANGELOG section", f"no non-empty '## {section_name(version)}' section")
    else:
        r.add("PASS", "CHANGELOG section", f"{len(section[1].splitlines())} lines")
        if stable:
            same = section[0] == today
            r.add("PASS" if same else "WARN", "CHANGELOG date", section[0] if same else f"{section[0]}, today is {today}")
    if stable:
        for path in (CHANGELOG, NUKE_MD):
            for line in table_rows(path, version):
                date = row_date(line)
                expected = section[0] if section else None
                ok = date == expected
                r.add("PASS" if ok else "FAIL", f"{path.name} row", date if ok else f"{date}, the section says {expected}")

        # The framework's own version, which is not in the source and has to be flipped by hand
        major, minor, patch, _, _ = parse(version)
        have = marketing_versions()
        ok = have == {f"{major}.{minor}.{patch}"}
        r.add("PASS" if ok else "FAIL", "MARKETING_VERSION", ", ".join(sorted(have)) + ("" if ok else f", expected {major}.{minor}.{patch}"))
    else:
        r.add("PASS", "MARKETING_VERSION", "left alone for a pre-release")

    # The generated files describe this commit
    p = run("make", "release-check", check=False)
    r.add("PASS" if p.returncode == 0 else "FAIL", "llms files fresh", "" if p.returncode == 0 else "make llms, on the commit to tag")
    if full:
        for target in ("snippets", "lint"):
            p = run("make", target, check=False)
            r.add("PASS" if p.returncode == 0 else "FAIL", f"make {target}", "" if p.returncode == 0 else (p.stdout + p.stderr)[-300:])

    # CI on this exact commit
    ci = run("gh", "run", "list", "--commit", head, "--json", "name,status,conclusion", "--jq",
             r'.[]|"\(.name)\t\(.status)\t\(.conclusion)"', check=False)
    runs = [l.split("\t") for l in ci.stdout.splitlines()] if ci.returncode == 0 else None
    if runs is None:
        r.add("WARN", "CI", "gh unavailable: unverified")
    elif not runs:
        r.add("FAIL", "CI", f"no run for {head[:8]}")
    elif any(status != "completed" for _, status, _ in runs):
        r.add("FAIL", "CI", "still running")
    elif any(c != "success" for _, _, c in runs):
        r.add("FAIL", "CI", ", ".join(f"{n}: {c}" for n, _, c in runs if c != "success"))
    else:
        r.add("PASS", "CI", f"{len(runs)} runs green")

    # The verdict of /nuke-pre-release-testing, for this commit and no other
    if skip_verdict:
        r.add("WARN", "pre-release check", "skipped with --skip-verdict")
    else:
        found, detail = verdict(version, head)
        r.add("PASS" if found == "GO" else "FAIL", "pre-release check", detail)
    return r.show()


# MARK: prepare

def prepare(version, date, hint=True):
    if git("status", "--porcelain"):
        sys.exit("The tree has uncommitted changes. Commit or stash them first: prepare commits only its own files.")
    stable = is_stable(version)
    touched = []

    if stable:
        text = CHANGELOG.read_text()
        section = changelog_section(text, version)
        if not section:
            sys.exit(f"CHANGELOG.md has no '## {section_name(version)}' section: write it first, in the voice of the others.")
        new = format_date(date)
        text = text.replace(f"## {section_name(version)}\n\n*{section[0]}*", f"## {section_name(version)}\n\n*{new}*", 1)
        touched.append(CHANGELOG)
        CHANGELOG.write_text(text)
        for path in (CHANGELOG, NUKE_MD):
            for line in table_rows(path, version):
                old = DATE_CELL.search(line).group(0)
                path.write_text(path.read_text().replace(line, line.replace(old, new.ljust(len(old)), 1), 1))
            if path not in touched and table_rows(path, version):
                touched.append(path)

        major, minor, patch, _, _ = parse(version)
        text = PBXPROJ.read_text()
        text = re.sub(r"MARKETING_VERSION = (?!1\.0;)[^;]+;", f"MARKETING_VERSION = {major}.{minor}.{patch};", text)
        PBXPROJ.write_text(text)
        touched.append(PBXPROJ)

        paths = [str(p.relative_to(ROOT)) for p in touched]
        if git("status", "--porcelain", "--", *paths):
            run("git", "add", *paths)
            run("git", "commit", "-m", f"Version {version}", "--", *paths)
            print(f"committed 'Version {version}': {', '.join(paths)}")
        else:
            print("version and date: nothing to change")

    # The llms files go in a commit of their own, so the diff of the release shows what changed for agents
    run("make", "llms")
    if git("status", "--porcelain", "--", *LLMS):
        run("git", "add", *LLMS)
        run("git", "commit", "-m", f"Regenerate llms.txt, llms-full.txt and llms-api.txt for {version}", "--", *LLMS)
        print("committed the llms files")
    else:
        print("llms files: already fresh")
    if hint:
        print(f"\nNothing is pushed. Review `git log -3 -p`, then `git push origin {git('rev-parse', '--abbrev-ref', 'HEAD')}`,\n"
              f"wait for CI on that commit, run /nuke-pre-release-testing {version}, and then `check`.")


# MARK: notes, tag, publish

def notes(version):
    section = changelog_section(CHANGELOG.read_text(), version)
    if not section or not section[1]:
        sys.exit(f"CHANGELOG.md has no '## {section_name(version)}' section")
    return section[1]


def is_latest(version):
    """The Latest badge goes to the highest stable version, so a 13.x patch after 14.0 doesn't take it."""
    if not is_stable(version):
        return False
    mine = parse(version)[:3]
    others = [parse(t)[:3] for t in git("tag").splitlines() if VERSION.match(t) and is_stable(t)]
    return all(mine >= o for o in others)


def do_tag(version):
    head = git("rev-parse", "HEAD")
    run("git", "tag", version, head)
    run("git", "push", "origin", version)
    print(f"tagged {version} at {head[:8]} and pushed it")


def release_command(version):
    """The `gh release create` command, and the notes it takes from a file."""
    body = notes(version)
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as f:
        f.write(body + "\n")
    cmd = ["gh", "release", "create", version, "--verify-tag", "--title", release_title(version), "--notes-file", f.name]
    cmd += ["--prerelease"] if not is_stable(version) else ["--latest"] if is_latest(version) else ["--latest=false"]
    return cmd, body


def tag_on_origin(version):
    return bool(git("ls-remote", "--tags", "origin", f"refs/tags/{version}"))


def release_exists(version):
    return run("gh", "release", "view", version, check=False).returncode == 0


# MARK: The guided release

class Quit(Exception):
    pass


class Session:
    """The run: what was decided at every step, and the notes, in .build/release/<version>.md."""

    def __init__(self, version, total):
        self.version, self.total, self.n = version, total, 0
        self.title = ""
        self.notes = []
        self.outcomes = []
        LOG_DIR.mkdir(parents=True, exist_ok=True)
        self.path = LOG_DIR / f"{version}.md"
        branch = git("rev-parse", "--abbrev-ref", "HEAD")
        self.write(f"\n# Release {version}, {datetime.datetime.now():%Y-%m-%d %H:%M}\n\n{branch} at {git('rev-parse', '--short=8', 'HEAD')}\n")

    def write(self, text):
        with self.path.open("a") as f:
            f.write(text + "\n")

    def begin(self, title, lines, outward=False):
        self.n += 1
        self.title = title
        print(f"\n━━ {self.n}/{self.total}  {title}" + ("   ⚠ outward-facing, can't be taken back" if outward else ""))
        for line in lines:
            print(f"   {line}")
        self.write(f"\n## {self.n}. {title}")

    def outcome(self, text):
        self.outcomes.append((self.title, text))
        self.write(f"- {text}")
        print(f"   → {text}")

    def note(self, text):
        if text.strip():
            self.notes.append((self.title, text.strip()))
            self.write(f"- note: {text.strip()}")

    def ask(self, options):
        """[y] [s] [n] [q] prompt; returns the key of the option chosen. [n] and [q] are always there."""
        menu = "  ".join(f"[{k}] {label}" for k, label in options.items()) + "  [n] note  [q] quit"
        while True:
            try:
                answer = input(f"   {menu} > ").strip().lower()
            except (EOFError, KeyboardInterrupt):
                print()
                raise Quit()
            if answer == "q":
                raise Quit()
            if answer == "n":
                try:
                    self.note(input("   note > "))
                except (EOFError, KeyboardInterrupt):
                    print()
                continue
            if answer in options:
                return answer
            print("   (an explicit answer, no default)")

    def step(self, title, lines, action, outward=False, label="do it"):
        """Prints the step, asks, and runs the action. A failure offers retry, skip, or quit."""
        self.begin(title, lines, outward)
        if self.ask({"y": label, "s": "skip"}) == "s":
            return self.outcome("skipped")
        while True:
            try:
                if action() is False:
                    raise SystemExit("it reported a failure, see above")
                return self.outcome("done")
            except SystemExit as e:
                print(f"   ✗ {e.code if isinstance(e.code, str) else 'failed'}")
            except KeyboardInterrupt:
                print("\n   ✗ interrupted")
            if self.ask({"r": "retry", "s": "skip anyway"}) == "s":
                return self.outcome("skipped after a failure, on purpose")

    def skip(self, title, reason):
        self.begin(title, [reason])
        self.outcome(f"nothing to do: {reason}")

    def finish(self):
        print(f"\n━━ Record of the run: {self.path}")
        for title, text in self.notes:
            print(f"   note ({title}): {text}")
        for title, text in self.outcomes:
            print(f"   {title}: {text}")


def stream(*cmd):
    """Runs a command with its output on the terminal, for the ones that take minutes."""
    if subprocess.run(cmd, cwd=ROOT).returncode != 0:
        sys.exit(f"`{' '.join(cmd)}` failed")


def wait_for_ci(head):
    """Polls the runs on a commit until they finish. True if they are all green."""
    started, last = time.time(), None
    while True:
        p = run("gh", "run", "list", "--commit", head, "--json", "name,status,conclusion", "--jq",
                r'.[]|"\(.name)\t\(.status)\t\(.conclusion)"', check=False)
        if p.returncode != 0:
            sys.exit("gh can't list the runs: " + p.stderr.strip())
        runs = [l.split("\t") for l in p.stdout.splitlines()]
        state = ", ".join(f"{n}: {c or s}" for n, s, c in runs) or "no runs yet"
        if state != last:
            print(f"   {datetime.datetime.now():%H:%M:%S}  {state}")
            last = state
        if runs and all(s == "completed" for _, s, _ in runs):
            return all(c == "success" for _, _, c in runs)
        if not runs and time.time() - started > 180:
            sys.exit(f"no run for {head[:8]} after 3 minutes: is CI triggered for this branch?")
        time.sleep(30)


def guided_release(version, date, full, skip_verdict):
    if not sys.stdin.isatty():
        sys.exit("This asks questions, so it needs a terminal. In Claude Code, run it as `! python3 .scripts/release.py "
                 f"{version}`. For what is read-only, `check` and `notes` run without one.")
    stable = is_stable(version)
    session = Session(version, total=8)
    branch = git("rev-parse", "--abbrev-ref", "HEAD")
    last = git("describe", "--tags", "--abbrev=0") if run("git", "describe", "--tags", "--abbrev=0", check=False).returncode == 0 else None

    print(f"Releasing {release_title(version)} from {branch}"
          + (f", {git('rev-list', '--count', f'{last}..HEAD')} commits after {last}" if last else ""))
    print(f"{'A stable release' if stable else 'A pre-release'}{', which takes Latest' if is_latest(version) else ''}. "
          f"The record of this run is {session.path}.")
    try:
        # 1. Prepare
        if stable:
            lines = [f"Date: {format_date(date)}",
                     f"CHANGELOG.md: the date of '## {section_name(version)}'" + (" and of its release-history row" if table_rows(CHANGELOG, version) else ""),
                     *(["Nuke.md: the row of the minimum-requirements table"] if table_rows(NUKE_MD, version) else []),
                     f"Nuke.xcodeproj: MARKETING_VERSION {', '.join(sorted(marketing_versions()))} → {'.'.join(map(str, parse(version)[:3]))}",
                     f"Commit 'Version {version}', then `make llms` in a commit of its own. Local: nothing is pushed."]
        else:
            lines = ["A pre-release has no date or version to write.", "Runs `make llms`, and commits the files if they changed. Local: nothing is pushed."]
        if git("status", "--porcelain"):
            lines.append("⚠ the tree has uncommitted changes: this will refuse until they are committed or stashed")
        session.step("Prepare the release commits", lines, lambda: prepare(version, date, hint=False))

        # 2. Push
        head = git("rev-parse", "HEAD")
        ahead = run("git", "log", "--oneline", f"origin/{branch}..HEAD", check=False).stdout.strip().splitlines()
        if run("git", "rev-parse", "--verify", f"origin/{branch}", check=False).returncode == 0 and not ahead:
            session.skip("Push the branch", f"origin/{branch} already has {head[:8]}")
        else:
            session.step("Push the branch", [f"git push origin {branch}", f"{len(ahead)} commits go with it:", *[f"  {l}" for l in ahead[:8]]],
                         lambda: run("git", "push", "origin", branch), outward=True)
        head = git("rev-parse", "HEAD")

        # 3. CI
        session.step("Wait for CI on the commit to tag",
                     [f"Polls GitHub every 30 s for the runs on {head[:8]}, up to as long as it takes. Ctrl-C stops it."],
                     lambda: wait_for_ci(head), label="wait")

        # 4. The verdict
        found, detail = verdict(version, head)
        if found == "GO":
            session.skip("Pre-release check", f"/nuke-pre-release-testing says GO for {head[:8]}")
        else:
            session.step("Pre-release check",
                         [f"This script can't run it. In Claude Code: /nuke-pre-release-testing {version}, on {head[:8]}.",
                          f"Looks for {CHECKS / f'{version}-{head[:8]}' / 'verdict.json'}",
                          "A verdict is for one commit: any commit after it needs a new one." + (" (--skip-verdict is on: the check below won't need it.)" if skip_verdict else "")],
                         lambda: verdict(version, head)[0] == "GO" or sys.exit(verdict(version, head)[1]),
                         label="it's done, look for it")

        # 5. Check
        session.step("Check that the commit can be tagged",
                     ["Pushed and clean, tag free, CHANGELOG section and dates, MARKETING_VERSION, llms files fresh, CI green on this SHA, the verdict."
                      + (" Plus `make snippets` and `make lint`." if full else ""), "Read-only."],
                     lambda: check(version, full, skip_verdict), label="run it")

        # 6. Tag
        head = git("rev-parse", "HEAD")
        if tag_on_origin(version):
            at = git("rev-list", "-n1", version)
            if at == head:
                session.skip("Tag", f"{version} is already on origin, at {head[:8]}")
            else:
                session.begin("Tag", [f"⚠ {version} is already on origin, at {at[:8]} and not {head[:8]}"])
                session.outcome("stopped: the tag points to another commit")
                raise Quit()
        else:
            session.step("Tag the commit",
                         [f"git tag {version} {head[:8]}   ({git('log', '-1', '--format=%s')})", f"git push origin {version}", "A lightweight tag, like every one before it."],
                         lambda: do_tag(version), outward=True)

        # 7. GitHub Release
        if release_exists(version):
            session.skip("GitHub Release", f"{release_title(version)} already exists")
        else:
            cmd, body = release_command(version)
            preview = body.splitlines()
            session.step("Create the GitHub Release",
                         [shlex.join(cmd), f"Notes: the CHANGELOG section, {len(preview)} lines. It starts:", *[f"  | {l}" for l in preview[:6]]],
                         lambda: print(run(*cmd).stdout.strip()), outward=True)

        # 8. Docs
        if not stable:
            session.skip("Documentation", "a pre-release doesn't replace what the site shows for everyone")
        else:
            site = {}

            def build():
                # Line by line, because the build takes minutes and the output is how you know it's alive
                proc = subprocess.Popen(["bash", str(ROOT / ".scripts/deploy-docs.sh")], cwd=ROOT, text=True,
                                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                output = []
                for line in proc.stdout:
                    print(f"   {line}", end="")
                    output.append(line)
                if proc.wait() != 0:
                    sys.exit("deploy-docs.sh failed")
                m = re.search(r"committed in (.+?): [0-9a-f]+ ", "".join(output))
                site["path"] = m.group(1) if m else None

            session.step("Build the documentation and commit it to kean-docs.github.io",
                         ["bash .scripts/deploy-docs.sh: builds the four sites (several minutes), copies them into the checkout of the site, commits there.",
                          "The site has no versions: this replaces the docs for everyone, so it is done at the tag. Local until the next step."],
                         build, label="build")
            if site.get("path"):
                session.step("Push kean-docs.github.io", [f"git -C {site['path']} push origin main", "The docs are live a minute or two after."],
                             lambda: run("git", "-C", site["path"], "push", "origin", "main"), outward=True)

        major, minor, patch, _, _ = parse(version)
        print(f"\nDone. Left for you: " + (f"delete release/{major}.{minor}, its CI draft PR and ci-{major}.{minor}-base, and put the {section_name(version)} section on main."
                                          if patch else "move the milestone and close the issues that shipped."))
    except Quit:
        session.outcome("stopped here")
    finally:
        session.finish()


def main():
    argv = sys.argv[1:]
    if argv and VERSION.match(argv[0]):
        argv.insert(0, "release")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("step", choices=["release", "check", "prepare", "notes"])
    ap.add_argument("version")
    ap.add_argument("--date", type=datetime.date.fromisoformat, default=datetime.date.today())
    ap.add_argument("--full", action="store_true")
    ap.add_argument("--skip-verdict", action="store_true")
    a = ap.parse_args(argv)
    parse(a.version)
    if a.step == "release":
        guided_release(a.version, a.date, a.full, a.skip_verdict)
    elif a.step == "check":
        sys.exit(0 if check(a.version, a.full, a.skip_verdict) else 1)
    elif a.step == "prepare":
        prepare(a.version, a.date)
    else:
        print(notes(a.version))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Check and bundle the DeepSeek harness phone-shell user guide.

    python3 app/tool/guide_sync.py           # check, then write app/assets/skills/dsh-app-guide/
    python3 app/tool/guide_sync.py --check   # check only, write nothing; exit 1 on any problem

The source is docs/guide/ (SKILL.md, README.md, zh/*.md, en/*.md). Bundled files
are flat in app/assets/skills/dsh-app-guide/; manifest.json maps asset names to
source-relative names and reports dshVersion for the native guide reader.
The current deepseek-harness-guide id and front-matter managed marker identify
this bundle. No previous guide id or marker is recognized. This script only
writes bundled assets, never installs a skill or changes user HOME.

- zh/ and en/ hold the same pages. README.md says `> DeepSeek harness <version>`;
  the source is the exact @deepseek-ai/dsh dependency in the official rc.3 lock's
  package.json. If a built runtime manifest exists, its dshVersion must agree.
- A UI path is a code span `A › B › C` on the line right after
  `<!-- nav: keyA,keyB,keyC -->`, which names each label's ARB key
  (app/lib/l10n/parts/*_<locale>.arb); a `›` without that line fails.
- **Bold** is for UI text only: each must be a label of that locale, from the
  ARB or the Android string resources.
- Relative links resolve inside docs/guide/. The guide has no native action links.
- Chinese pages say 对话, never 会话, and never 实验.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SKILL = 'deepseek-harness-guide'
LOCALES = ('zh', 'en')
NAV = re.compile(r'^<!-- nav: ([A-Za-z][A-Za-z0-9_]*(?:,[A-Za-z][A-Za-z0-9_]*)*) -->$')
SPAN = re.compile(r'`([^`\n]+)`')
BOLD = re.compile(r'\*\*([^*\n]+)\*\*')
LINK = re.compile(r'\]\(([^)\s]+)\)')
VERSION_LINE = re.compile(r'^> DeepSeek harness (\S+)$', re.MULTILINE)
OFFICIAL_PACKAGE = Path('runtime/locks/dsh-0.2.2-rc.3/package.json')
EXACT_VERSION = re.compile(r'(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)'
                           r'(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?'
                           r'(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?')
RUNTIME_MANIFEST = Path('runtime/out/arm64-v8a/assets/runtime/manifest.json')
BANNED = {'zh': ('会话', '实验'), 'en': ()}


def read_arb(directory: Path, locale: str) -> dict[str, str]:
    labels: dict[str, str] = {}
    files = sorted(directory.glob(f'*_{locale}.arb'))
    if not files:
        raise ValueError(f'{directory}: no *_{locale}.arb')
    for file in files:
        for key, value in json.loads(file.read_text(encoding='utf-8')).items():
            if key.startswith('@') or not isinstance(value, str):
                continue
            if key in labels:
                raise ValueError(f'{file.name}: duplicate key {key}')
            labels[key] = value
    return labels


def read_android(res: Path, locale: str) -> set[str]:
    folder = res / ('values-zh' if locale == 'zh' else 'values')
    out: set[str] = set()
    for file in sorted(folder.glob('*.xml')):
        for node in ET.parse(file).getroot().iter('string'):
            text = ''.join(node.itertext())
            out.add(text.replace("\\'", "'").replace('\\"', '"'))
    return out


def dsh_version(repo: Path) -> str:
    package = repo / OFFICIAL_PACKAGE
    data = json.loads(package.read_text(encoding='utf-8'))
    dependencies = data.get('dependencies') if isinstance(data, dict) else None
    version = dependencies.get('@deepseek-ai/dsh') if isinstance(dependencies, dict) else None
    if not isinstance(version, str) or not EXACT_VERSION.fullmatch(version):
        raise ValueError(f'{package}: dependencies["@deepseek-ai/dsh"] must be an exact version')
    manifest = repo / RUNTIME_MANIFEST
    if manifest.exists():
        runtime = json.loads(manifest.read_text(encoding='utf-8'))
        built_version = runtime.get('dshVersion') if isinstance(runtime, dict) else None
        if built_version != version:
            raise ValueError(f'{manifest}: dshVersion must match {OFFICIAL_PACKAGE.as_posix()} '
                             f'@deepseek-ai/dsh {version}, found {built_version!r}')
    return version


def check_page(path: Path, guide: Path, locale: str, arb: dict[str, str], labels: set[str]) -> list[str]:
    name = path.relative_to(guide).as_posix()
    lines = path.read_text(encoding='utf-8').splitlines()
    errors: list[str] = []
    annotated: set[int] = set()
    for i, line in enumerate(lines):
        if '<!--' not in line:
            continue
        match = NAV.match(line)
        if not match:
            errors.append(f'{name}:{i + 1}: malformed annotation (want <!-- nav: key1,key2 -->)')
            continue
        values = []
        for key in match[1].split(','):
            value = arb.get(key)
            if value is None:
                errors.append(f'{name}:{i + 1}: no {locale} ARB key {key}')
            elif not value or any(c in value for c in '{}`›\n'):
                errors.append(f'{name}:{i + 1}: {key} is not a plain label')
            else:
                values.append(value)
        if len(values) != len(match[1].split(',')):
            continue
        expected = ' › '.join(values)
        if i + 1 >= len(lines) or expected not in SPAN.findall(lines[i + 1]):
            errors.append(f'{name}:{i + 2}: want `{expected}` on the line after the annotation')
            continue
        annotated.add(i + 1)
        extra = [s for s in SPAN.findall(lines[i + 1]) if '›' in s and s != expected]
        if extra:
            errors.append(f'{name}:{i + 2}: one path per line; unannotated {extra}')
    for i, line in enumerate(lines):
        if '›' in line and i not in annotated:
            errors.append(f'{name}:{i + 1}: path without a nav annotation')
        for bold in BOLD.findall(line):
            if bold not in labels:
                errors.append(f'{name}:{i + 1}: **{bold}** is not a {locale} UI label')
        for word in BANNED[locale]:
            if word in line:
                errors.append(f'{name}:{i + 1}: avoid 「{word}」')
    return errors + check_links(path, guide)


def check_links(path: Path, guide: Path) -> list[str]:
    name = path.relative_to(guide).as_posix()
    errors: list[str] = []
    for i, line in enumerate(path.read_text(encoding='utf-8').splitlines()):
        for target in LINK.findall(line):
            if not re.match(r'(https?|mailto):', target):
                file = (path.parent / target.split('#')[0]).resolve()
                if not file.is_file() or guide.resolve() not in file.parents:
                    errors.append(f'{name}:{i + 1}: broken link {target}')
    return errors


def check_skill(text: str) -> list[str]:
    front = re.match(r'---\n([\s\S]*?)\n---\n', text)
    if not front:
        return ['SKILL.md: must start with --- front matter']
    lines = front[1].splitlines()
    errors = []
    if not any(line.startswith('# deepseek-harness:managed') for line in lines):
        errors.append('SKILL.md: front matter needs the # deepseek-harness:managed line')
    for key in ('name', 'description', 'whenToUse'):
        if not any(line.startswith(f'{key}: ') for line in lines):
            errors.append(f'SKILL.md: front matter needs {key}')
    if f'name: {SKILL}' not in lines:
        errors.append(f'SKILL.md: name must be {SKILL}')
    for line in lines:
        # Plain YAML scalars: one more `: ` or ` #` and DSH can't read the skill.
        key, _, value = line.partition(': ')
        if not line.startswith('#') and (': ' in value or ' #' in value or value[:1] in '\'"[]{}&*!|>%@`'):
            errors.append(f'SKILL.md: {key} must be a plain one-line value (no ": ", " #" or leading quote)')
    return errors


def guide_files(guide: Path) -> dict[str, Path]:
    files = {'SKILL.md': guide / 'SKILL.md', 'README.md': guide / 'README.md'}
    for locale in LOCALES:
        for page in sorted((guide / locale).glob('*.md')):
            files[f'{locale}/{page.name}'] = page
    return files


def check(repo: Path, guide: Path) -> list[str]:
    errors: list[str] = []
    for required in ('SKILL.md', 'README.md'):
        if not (guide / required).is_file():
            return [f'{guide}: missing {required}']
    pages = {locale: {p.name for p in (guide / locale).glob('*.md')} for locale in LOCALES}
    if not pages['zh']:
        errors.append(f'{guide}/zh: no pages')
    if pages['zh'] != pages['en']:
        errors.append(f'zh/en pages differ: only zh {sorted(pages["zh"] - pages["en"])}, '
                      f'only en {sorted(pages["en"] - pages["zh"])}')
    for other in guide.rglob('*'):
        rel = other.relative_to(guide).as_posix()
        if other.is_file() and rel not in guide_files(guide):
            errors.append(f'{rel}: not part of the guide (SKILL.md, README.md, zh/*.md, en/*.md)')
    version = dsh_version(repo)
    readme = (guide / 'README.md').read_text(encoding='utf-8')
    stated = VERSION_LINE.findall(readme)
    if stated != [version]:
        errors.append(f'README.md: want one line `> DeepSeek harness {version}` '
                      f'({OFFICIAL_PACKAGE.as_posix()} @deepseek-ai/dsh), found {stated}')
    errors += check_skill((guide / 'SKILL.md').read_text(encoding='utf-8'))
    res = repo / 'app/android/app/src/main/res'
    for locale in LOCALES:
        arb = read_arb(repo / 'app/lib/l10n/parts', locale)
        labels = set(arb.values()) | read_android(res, locale)
        for page in sorted((guide / locale).glob('*.md')):
            errors += check_page(page, guide, locale, arb, labels)
    for name in ('SKILL.md', 'README.md'):
        errors += check_links(guide / name, guide)
    return errors


def assets(guide: Path, version: str) -> dict[str, bytes]:
    files = guide_files(guide)
    manifest = {target.replace('/', '-'): target for target in files}
    out = {flat: files[target].read_bytes() for flat, target in manifest.items()}
    out['manifest.json'] = (json.dumps({'name': SKILL, 'dshVersion': version, 'files': manifest},
                                      ensure_ascii=False, indent=2) + '\n').encode()
    return out


def sync(directory: Path, files: dict[str, bytes], write: bool) -> list[str]:
    current = {p.name for p in directory.glob('*') if p.is_file()} if directory.is_dir() else set()
    stale = sorted(current - files.keys())
    changed = sorted(n for n, data in files.items()
                     if not (directory / n).is_file() or (directory / n).read_bytes() != data)
    if not write:
        return [f'{directory}: out of date ({", ".join(stale + changed)}); run python3 app/tool/guide_sync.py']\
            if stale or changed else []
    directory.mkdir(parents=True, exist_ok=True)
    for name in stale:
        (directory / name).unlink()
    for name in changed:
        (directory / name).write_bytes(files[name])
    return []


def run(repo: Path, write: bool) -> list[str]:
    guide = repo / 'docs/guide'
    errors = check(repo, guide)
    if errors:
        return errors
    # The manifest identifies the current guide bundle; no alias is emitted.
    return sync(repo / 'app/assets/skills/dsh-app-guide',
                assets(guide, dsh_version(repo)), write)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--check', action='store_true', help='check only, write nothing')
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    try:
        errors = run(args.repo, write=not args.check)
    except (OSError, ValueError, ET.ParseError) as error:
        errors = [str(error)]
    for error in errors:
        print(f'guide: {error}', file=sys.stderr)
    if errors:
        return 1
    count = len(guide_files(args.repo / 'docs/guide'))
    print(f'guide: {count} files {"checked" if args.check else "checked and built"}')
    return 0


if __name__ == '__main__':
    # CLI output is UTF-8 even when redirected through a legacy-codepage pipe.
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(encoding='utf-8', errors=stream.errors)
    raise SystemExit(main())

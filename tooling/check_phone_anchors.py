#!/usr/bin/env python3
"""Check the phone layout's anchors against an installed DSH tree.

The Lite phone layout is injected CSS/JS (app/assets/web) over DSH Web's DOM: it
targets data-slot names, data-* attributes and CSS-module class *suffixes* rather
than per-build hashes. This lists what those files depend on and whether the
given tree still carries each one, so an engine swap (official update) is checked
before anyone looks at a phone.

    python3 tooling/check_phone_anchors.py <dsh-prefix>
    python3 tooling/check_phone_anchors.py .harness-tmp-rc2/prefix

Exit 1 when an anchor is missing: the phone layout would silently degrade there.
"""
from __future__ import annotations

import pathlib
import re
import sys

WEB = pathlib.Path(__file__).resolve().parents[1] / 'app/assets/web'
SOURCES = ('dsh_web_phone.css', 'dsh_web_phone.js', 'dsh_web_sidebar.js', 'dsh_web_modal.js', 'dsh_web_header.js')

SLOT = re.compile(r'data-slot="([^"]+)"')
ATTR = re.compile(r'\b(data-[a-z0-9-]+)')
CLASS = re.compile(r'\[class\*="_([A-Za-z0-9]+)"\]')
VAR = re.compile(r'(--dsh-[a-z0-9-]+)')

# Watched, not targeted: the phone script observes these to re-sync the page
# background, and it also observes `class`, which is how DSH switches themes.
# A build that drops them keeps working; it only loses a redundant trigger.
ADVISORY = {'data-theme', 'data-color-scheme'}


def anchors() -> dict[str, set[str]]:
    slots, attrs, classes, vars_ = set(), set(), set(), set()
    for name in SOURCES:
        text = (WEB / name).read_text(encoding='utf-8')
        slots.update(SLOT.findall(text))
        attrs.update(a for a in ATTR.findall(text))
        classes.update(CLASS.findall(text))
        vars_.update(VAR.findall(text))
    # data-slot itself is covered by the slot check.
    attrs.discard('data-slot')
    return {'slot': slots, 'attribute': attrs, 'class': classes, 'variable': vars_}


def corpus(prefix: pathlib.Path) -> list[str]:
    out = []
    for pattern in ('*.js', '*.css', '*.mjs', '*.cjs'):
        for path in prefix.rglob(pattern):
            if 'node_modules' not in path.parts:
                continue
            try:
                out.append(path.read_text('utf-8', 'replace'))
            except OSError:
                pass
    return out


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    prefix = pathlib.Path(sys.argv[1])
    if not prefix.is_dir():
        print('not a directory:', prefix)
        return 2
    texts = corpus(prefix)
    found = anchors()
    missing, advisory = [], []
    for kind, names in found.items():
        for name in sorted(names):
            # Ours, not DSH's: the app injects these onto the page itself.
            if name.startswith('data-dsh-app') or name.startswith('--dsh-app'):
                continue
            if kind == 'slot':
                # The attribute is often built from a slot name constant, so the
                # bare quoted name counts as present.
                needles = ['data-slot="%s"' % name, '"%s"' % name, "'%s'" % name]
            elif kind == 'attribute':
                needles = [name]
            elif kind == 'class':
                needles = ['_' + name]
            else:
                needles = [name]
            if any(n in text for n in needles for text in texts):
                continue
            (advisory if name in ADVISORY else missing).append((kind, name))
    total = sum(len(v) for v in found.values())
    print('phone-layout anchors: %d (%s)' % (total, ', '.join('%s %d' % (k, len(v)) for k, v in found.items())))
    print('dsh tree:', prefix, '| files scanned:', len(texts))
    for kind, name in advisory:
        print('ADVISORY %-9s %s (watched only; `class` still triggers)' % (kind, name))
    for kind, name in missing:
        print('MISSING  %-9s %s' % (kind, name))
    if missing:
        print('%d anchor(s) missing: the phone layout needs re-vetting there.' % len(missing))
        return 1
    print('every anchor the phone layout targets is still present.')
    return 0


if __name__ == '__main__':
    sys.exit(main())

#!/usr/bin/env python3
"""cast-markers.py IN.cast OUT.cast 'PATTERN::LABEL' ...
Insert an asciicast marker event ("m") right AFTER the first output event whose text contains PATTERN.
`asciinema play -m OUT.cast` (-m = --pause-on-markers, asciinema 3.x) then pauses with the trap line
already on screen; <space> resumes.
Works for asciicast v2 (absolute timestamps) and v3 (intervals since the previous event)."""
import json, sys

src, dst, specs = sys.argv[1], sys.argv[2], sys.argv[3:]
todo = [s.split('::', 1) for s in specs]
with open(src, encoding='utf-8') as f:
    lines = f.read().splitlines()
header = json.loads(lines[0]); version = header.get('version')
if version not in (2, 3):
    sys.exit(f'unsupported asciicast version {version}')
out = [lines[0]]
for line in lines[1:]:
    if not line.strip() or line.lstrip().startswith('#'):   # v3 allows comment lines
        out.append(line); continue
    t, code, data = json.loads(line)
    out.append(line)
    if code == 'o':
        for spec in list(todo):
            pat, label = spec
            if pat in data:
                # v3: interval 0 = same instant as this event; v2: same absolute time as this event
                out.append(json.dumps([0.0 if version == 3 else t, 'm', label]))
                todo.remove(spec)
for pat, label in todo:
    print(f'WARNING: pattern not found, no marker: {pat!r} ({label})', file=sys.stderr)
with open(dst, 'w', encoding='utf-8') as f:
    f.write('\n'.join(out) + '\n')
print(f'wrote {dst}: {len(specs) - len(todo)} marker(s), asciicast v{version}')

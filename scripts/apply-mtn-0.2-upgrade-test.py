#!/usr/bin/env python3
from pathlib import Path

p = Path("apps/kernel/test/motoko/run.ts")
text = p.read_text()
needle = '  "authorization_service_test.mo",\n'
addition = needle + '  "authorization_upgrade_persistence_test.mo",\n'
if '"authorization_upgrade_persistence_test.mo"' not in text:
    if needle not in text:
        raise SystemExit("authorization_service_test.mo runner entry missing")
    text = text.replace(needle, addition, 1)
p.write_text(text)

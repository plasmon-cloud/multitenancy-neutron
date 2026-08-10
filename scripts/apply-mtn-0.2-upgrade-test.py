#!/usr/bin/env python3
from pathlib import Path

runner = Path("apps/kernel/test/motoko/run.ts")
text = runner.read_text()
needle = '  "authorization_service_test.mo",\n'
addition = needle + '  "authorization_upgrade_persistence_test.mo",\n'
if '"authorization_upgrade_persistence_test.mo"' not in text:
    if needle not in text:
        raise SystemExit("authorization_service_test.mo runner entry missing")
    text = text.replace(needle, addition, 1)
runner.write_text(text)

test = Path("apps/kernel/test/motoko/authorization_service_test.mo")
text = test.read_text()
old = '''        assert (request.authorization.resource == note);\n        assert (request.authorization.rights == [#read]);\n        Text.encodeUtf8("provider-ok");\n'''
new = '''        assert (request.authorization.resource == note);\n        if (request.operation == "read") {\n            assert (request.authorization.rights == [#read]);\n        } else if (request.operation == "write") {\n            assert (request.authorization.rights == [#read, #write]);\n        };\n        Text.encodeUtf8("provider-ok");\n'''
if old in text:
    text = text.replace(old, new, 1)
test.write_text(text)

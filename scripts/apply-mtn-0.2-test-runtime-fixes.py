#!/usr/bin/env python3
from pathlib import Path

p = Path("apps/kernel/test/motoko/authorization_service_test.mo")
text = p.read_text()
old = '''        assert (request.authorization.resource == note);\n        assert (request.authorization.rights == [#read]);\n        Text.encodeUtf8("provider-ok");\n'''
new = '''        assert (request.authorization.resource == note);\n        if (request.operation == "read") {\n            assert (request.authorization.rights == [#read]);\n        } else if (request.operation == "write") {\n            assert (request.authorization.rights == [#read, #write]);\n        };\n        Text.encodeUtf8("provider-ok");\n'''
if old not in text:
    raise SystemExit("provider callback rights assertion target missing")
p.write_text(text.replace(old, new, 1))

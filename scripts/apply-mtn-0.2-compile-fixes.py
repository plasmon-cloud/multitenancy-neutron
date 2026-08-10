#!/usr/bin/env python3
from pathlib import Path

p = Path("apps/kernel/backend/authorization/Service.mo")
text = p.read_text()
text = text.replace(
    '    let ANONYMOUS = Principal.fromText("2vxsx-fae");\n',
    '    let ANONYMOUS_TEXT = "2vxsx-fae";\n',
    1,
)
text = text.replace('caller == ANONYMOUS', 'isAnonymous(caller)')
text = text.replace('principal != ANONYMOUS', 'not isAnonymous(principal)')
marker = '''        func audienceAllows(\n'''
helper = '''        func isAnonymous(principal : Principal) : Bool {\n            Principal.toText(principal) == ANONYMOUS_TEXT;\n        };\n\n'''
if helper not in text:
    text = text.replace(marker, helper + marker, 1)
p.write_text(text)

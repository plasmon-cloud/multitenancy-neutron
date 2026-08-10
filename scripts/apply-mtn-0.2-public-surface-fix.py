#!/usr/bin/env python3
from pathlib import Path

p = Path("packages/neutron-motoko-capabilities/src/lib.mo")
text = p.read_text()
text = text.replace(
    "// multitenancy-neutron 0.2 resource-authorization contracts. AppScope is\n"
    "    // the existing Neutron installation identity; ResourceRef is provider-defined.\n",
    "// multitenancy-neutron 0.2 resource-authorization contracts. The installation\n"
    "    // reference is the existing Neutron installation identity; ResourceRef is provider-defined.\n",
    1,
)
text = text.replace(
    "AuthorizationAppScopeRefV1",
    "AuthorizationInstallationRefV1",
)
p.write_text(text)

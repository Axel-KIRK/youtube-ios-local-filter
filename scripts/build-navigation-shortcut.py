#!/usr/bin/env python3
"""Generate a fixed certificate Settings navigation experiment; optionally sign with Apple's CLI.

The unsigned file is a source artifact, not an installable shortcut. Signing
requires an iCloud session on the build Mac. No account data belongs in this file.
"""

import argparse
import plistlib
from pathlib import Path
import subprocess
import uuid


DESTINATIONS = {
    "profiles": ("LocalFilter Profiles", "prefs:root=General&path=ManagedConfigurationList"),
    "trust": ("LocalFilter Trust", "prefs:root=General&path=About/CERT_TRUST_SETTINGS"),
}


def workflow(destination):
    url_action_id = str(uuid.uuid5(uuid.NAMESPACE_URL, destination)).upper()
    return {
        "WFWorkflowClientVersion": "3036.0.4.2",
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowHasOutputFallback": False,
        "WFWorkflowIcon": {
            "WFWorkflowIconGlyphNumber": 59666,
            "WFWorkflowIconStartColor": 1440408063,
        },
        "WFWorkflowTypes": [],
        "WFWorkflowInputContentItemClasses": [],
        "WFWorkflowOutputContentItemClasses": [],
        "WFWorkflowImportQuestions": [],
        "WFWorkflowActions": [
            {
                "WFWorkflowActionIdentifier": "is.workflow.actions.url",
                "WFWorkflowActionParameters": {
                    "UUID": url_action_id,
                    "WFURLActionURL": destination,
                },
            },
            {
                "WFWorkflowActionIdentifier": "is.workflow.actions.openurl",
                "WFWorkflowActionParameters": {
                    "WFInput": {
                        "Value": {
                            "OutputUUID": url_action_id,
                            "OutputName": "URL",
                            "Type": "ActionOutput",
                        },
                        "WFSerializationType": "WFTextTokenAttachment",
                    },
                },
            },
            {
                "WFWorkflowActionIdentifier": "is.workflow.actions.nothing",
                "WFWorkflowActionParameters": {},
            },
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("local-evidence/navigation-shortcuts"))
    parser.add_argument("--sign", action="store_true", help="Ask Apple's shortcuts CLI to sign for distribution")
    parser.add_argument("--destination", choices=DESTINATIONS, default="profiles")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    name, destination = DESTINATIONS[args.destination]
    unsigned = args.output / f"{name}.unsigned.shortcut"
    unsigned.write_bytes(plistlib.dumps(workflow(destination), sort_keys=True))
    print(f"Unsigned source: {unsigned}")
    if args.sign:
        signed = args.output / f"{name}.shortcut"
        subprocess.run([
            "shortcuts", "sign", "--mode", "anyone",
            "--input", str(unsigned), "--output", str(signed),
        ], check=True)
        print(f"Signed candidate (import still needs testing): {signed}")


if __name__ == "__main__":
    main()

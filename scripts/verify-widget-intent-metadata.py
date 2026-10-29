#!/usr/bin/env python3
"""Check what WidgetKit can actually see in the compiled iOS intent metadata."""
import json
import sys
from pathlib import Path


def main(path: str) -> None:
    metadata = json.loads(Path(path).read_text(encoding="utf-8"))
    intent = metadata["actions"]["DesktopStyledWidgetConfigurationIntent"]
    switch = intent["actionConfiguration"]["switchStatement"]["wrapper"]
    assert switch["parameterIdentifier"] == "content"
    cases = switch["cases"]

    def parameters_for(value: str) -> set:
        for case in cases:
            choices = case.get("value", {}).get("array", {}).get("values", [])
            if any(choice.get("enumeration", {}).get("value") == value for choice in choices):
                return set(case["configuration"]["actionSummary"]["wrapper"]["otherParameterIdentifiers"])
        raise AssertionError(f"missing WidgetKit configuration case: {value}")

    for provider in ("glmQuota", "openAIQuota", "mimoQuota", "deepSeekQuota"):
        required = {"quotaStyle", "quotaPeriod", "quotaTextColor"}
        missing = required - parameters_for(provider)
        assert not missing, f"{provider} missing parameters: {sorted(missing)}"
    for clock in ("compactTimeA", "compactTimeB", "compactTimeC"):
        required = {"compactTimeTextColor", "compactTimeAccentColor"}
        missing = required - parameters_for(clock)
        assert not missing, f"{clock} missing parameters: {sorted(missing)}"
    print("WidgetKit intent metadata: quota and clock configuration cases verified")


if __name__ == "__main__":
    main(sys.argv[1])

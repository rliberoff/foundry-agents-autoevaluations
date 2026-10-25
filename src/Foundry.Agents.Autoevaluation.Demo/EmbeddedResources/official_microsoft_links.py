import re


ALLOWED_HOSTS = frozenset(
    {
        "learn.microsoft.com",
        "azure.microsoft.com",
        "techcommunity.microsoft.com",
        "devblogs.microsoft.com",
        "support.microsoft.com",
    }
)


def response_text(value: object) -> str:
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        return "\n".join(response_text(part) for part in value)
    if isinstance(value, dict):
        if value.get("role", "assistant") != "assistant":
            return ""
        return response_text(value.get("content", value.get("text", "")))
    return ""


def grade(sample: dict, item: dict) -> float:
    """Check explicit web URLs, not the truth or completeness of a response."""
    if not isinstance(item, dict):
        return 0.0

    response = response_text(item.get("response"))
    if not response.strip():
        return 0.0

    urls = re.findall(
        r"(?:[a-z][a-z0-9+.-]*://|//|www\.)[^\s<>\[\]\"']*",
        response,
        flags=re.IGNORECASE,
    )
    for url in urls:
        match = re.fullmatch(
            r"https://([^/?#:@\\]+)(?::([0-9]+))?(?:[/?#][^\\]*)?",
            url.rstrip(".,;:!?)]}"),
            flags=re.IGNORECASE,
        )
        if match is None:
            return 0.0
        host, port = match.groups()
        if (
            host.lower().rstrip(".") not in ALLOWED_HOSTS
            or (port is not None and port.lstrip("0") != "443")
        ):
            return 0.0

    return 1.0

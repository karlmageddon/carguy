import re
import unicodedata


def normalize(value: str) -> str:
    value = "".join(c for c in unicodedata.normalize("NFD", value.casefold()) if not unicodedata.combining(c))
    return " ".join("".join(c if c.isalnum() or c in ".+-" else " " for c in value).split())


def grade(response: str, fact) -> bool:
    normalized = normalize(response)
    if not normalized:
        return False
    if normalized in {normalize(x) for x in [fact.answer, *fact.accepted_answers]}:
        return True
    if not fact.numeric_answer:
        return False
    match = re.fullmatch(r"\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+))\s*(.*?)\s*", response)
    if not match:
        return False
    rule = fact.numeric_answer
    for scale in rule.units:
        if normalize(scale.unit) == normalize(match[2]):
            return (
                abs(float(match[1]) * scale.multiplier - rule.value)
                <= rule.tolerance + max(abs(rule.value), 1) * 1e-12
            )
    return False

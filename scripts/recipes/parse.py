"""Turns a Cookbook page's wikitext into a recipe: name, servings, time, ingredient lines and method steps."""

import html
import re

INGREDIENT_HEADINGS = re.compile(r"^ingredients?\b", re.I)
STEP_HEADINGS = re.compile(r"^(procedure|directions?|method|preparation|instructions?|steps?|cooking)\b", re.I)


def clean(text):
    """Wiki markup to plain text: links to their labels, templates, references, HTML and emphasis removed."""
    text = re.sub(r"<ref[^>]*/>|<ref[^>]*>.*?</ref>", "", text, flags=re.S)
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    for _ in range(3):  # nested templates
        text = re.sub(r"\{\{[^{}]*\}\}", "", text)
    text = re.sub(r"\[\[(?:File|Image):[^\]]*\]\]", "", text, flags=re.I)
    text = re.sub(r"\[\[[^\]|]*\|([^\]]*)\]\]", r"\1", text)
    text = re.sub(r"\[\[([^\]]*)\]\]", lambda m: m.group(1).split(":")[-1], text)
    text = re.sub(r"\[https?://\S+\s+([^\]]*)\]", r"\1", text)
    text = re.sub(r"\[https?://\S+\]", "", text)
    text = re.sub(r"<[^>]+>", "", text)
    text = text.replace("'''", "").replace("''", "")
    text = html.unescape(text)
    return re.sub(r"\s+", " ", text).strip()


def summary(text):
    """The {{recipe summary}} fields (servings, time, category, difficulty), lower-cased keys."""
    match = re.search(r"\{\{\s*recipe\s*summary(.*?)\}\}", text, re.I | re.S)
    if not match:
        return {}
    body = re.sub(r"\[\[[^\]]*\]\]", "", match.group(1))  # the image link holds '|' too
    fields = {}
    for part in body.split("|"):
        if "=" in part:
            key, value = part.split("=", 1)
            fields[key.strip().lower()] = clean(value)
    return fields


def sections(text):
    """[(heading, lines)] for the page's sections, in order; level doesn't matter."""
    result, heading, lines = [], "", []
    for line in text.splitlines():
        match = re.match(r"^(=+)\s*(.*?)\s*\1\s*$", line.strip())
        if match:
            result.append((heading, lines))
            heading, lines = clean(match.group(2)), []
        else:
            lines.append(line)
    result.append((heading, lines))
    return result


def ingredient_lines(text):
    """The bulleted lines of the Ingredients section (and its subsections), cleaned."""
    lines, inside = [], False
    for heading, body in sections(text):
        if INGREDIENT_HEADINGS.match(heading):
            inside = True
        elif inside and (STEP_HEADINGS.match(heading) or heading.lower() in ("notes", "notes, tips, and variations",
                                                                              "see also", "references", "variations")):
            inside = False
        if inside:
            for line in body:
                if re.match(r"^\s*\*+", line):
                    cleaned = clean(re.sub(r"^\s*\*+", "", line))
                    if cleaned:
                        lines.append(cleaned)
    return lines


def steps(text):
    """The numbered lines of the method section, cleaned."""
    result = []
    for heading, body in sections(text):
        if STEP_HEADINGS.match(heading):
            for line in body:
                if re.match(r"^\s*#+(?![#:*])", line):
                    cleaned = clean(re.sub(r"^\s*#+", "", line))
                    if cleaned:
                        result.append(cleaned)
    return result


def servings(fields):
    """'4-6' → 4, '2 people' → 2; None when missing."""
    match = re.search(r"\d+", fields.get("servings", "") or fields.get("yield", ""))
    value = int(match.group()) if match else None
    return value if value and 1 <= value <= 20 else None


def minutes(fields):
    """Total time in minutes from '1 hour 20 minutes', '45 min', '1½ hours'; None when unknown."""
    text = (fields.get("time") or "").lower().replace("½", ".5").replace("¼", ".25").replace("¾", ".75")
    total = 0.0
    for number, unit in re.findall(r"(\d+(?:\.\d+)?)\s*(h|hr|hrs|hour|hours|m|min|mins|minute|minutes)\b", text):
        total += float(number) * (60 if unit.startswith("h") else 1)
    return int(total) if 0 < total <= 24 * 60 else None


def name(title):
    """'Cookbook:Potato Curry (Aloo Masala)' → 'Potato Curry (Aloo Masala)'."""
    return title.split(":", 1)[-1].strip()

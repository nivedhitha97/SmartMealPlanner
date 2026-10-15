"""Reads the data server-rendered web pages embed for their front end (Next.js and Nuxt)."""

import json
import re

_NEXT = re.compile(r'<script[^>]*id="__NEXT_DATA__"[^>]*>(.*?)</script>', re.S)
_NUXT = re.compile(r'<script[^>]*id="__NUXT_DATA__"[^>]*>(.*?)</script>', re.S)

# Nuxt wraps some values in a type tag: ["Reactive", index], ["Date", "2026-…"], ["Set", i, j, …].
_WRAPPERS = {"ShallowReactive", "Reactive", "Ref", "ShallowRef", "EmptyRef", "EmptyShallowRef", "NuxtError", "Island"}


def page_data(html):
    """The page's embedded data as plain JSON values, or None if it has none."""
    match = _NEXT.search(html)
    if match:
        return json.loads(match.group(1))
    match = _NUXT.search(html)
    if match:
        return devalue(json.loads(match.group(1)))
    return None


def devalue(table):
    """Decodes a Nuxt 3 payload, where every value is an index into one flat array."""
    memo = {}

    def value(index):
        if not isinstance(index, int) or not 0 <= index < len(table):
            return None
        if index in memo:
            return memo[index]
        raw = table[index]
        if isinstance(raw, list):
            if raw and isinstance(raw[0], str) and (raw[0] in _WRAPPERS or raw[0] in ("Set", "Map", "Date")):
                tag = raw[0]
                if tag == "Date":
                    result = raw[1]
                elif tag == "Set":
                    result = [value(i) for i in raw[1:]]
                elif tag == "Map":
                    result = {str(value(raw[k])): value(raw[k + 1]) for k in range(1, len(raw) - 1, 2)}
                else:
                    result = value(raw[1]) if len(raw) > 1 else None
                memo[index] = result
                return result
            result = []
            memo[index] = result  # set before recursing: payloads can be cyclic
            result.extend(value(i) for i in raw)
            return result
        if isinstance(raw, dict):
            result = {}
            memo[index] = result
            for key, i in raw.items():
                result[key] = value(i)
            return result
        memo[index] = raw
        return raw

    return value(0)


def find_objects(data, required_keys):
    """Every dict anywhere in `data` that has all of `required_keys`."""
    found, seen, stack = [], set(), [data]
    while stack:
        node = stack.pop()
        if id(node) in seen:
            continue
        seen.add(id(node))
        if isinstance(node, dict):
            if all(key in node for key in required_keys):
                found.append(node)
            stack.extend(node.values())
        elif isinstance(node, list):
            stack.extend(node)
    return found

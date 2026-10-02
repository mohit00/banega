"""Render docs/legal/{privacy-policy,terms-of-service}.md to self-contained HTML pages.

    python docs/legal/site/build_site.py

No dependencies. Handles the subset of Markdown the legal docs use: headings (with an
optional ``{#id}``), paragraphs, one level of nested bullets, numbered lists, tables,
blockquotes, horizontal rules, **bold**, *italic*, `code` and [links](url).

Reviewer notes (paragraphs or list items that start with a back-ticked ``[Note``) are left
out of the public pages; ``[PLACEHOLDERS]`` are highlighted so nothing unfilled ships
unnoticed. The DRAFT banner stays until the markdown's banner line is removed.
"""

from __future__ import annotations

import html
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
LEGAL = HERE.parent

PAGES = [
    ("privacy-policy.md", "privacy.html", "Banega Privacy Policy", "Privacy Policy"),
    ("terms-of-service.md", "terms.html", "Banega Terms of Service", "Terms of Service"),
]

CSS = """
:root{--haldi:#FFCC33;--haldi-deep:#E0A800;--green:#0E7C3A;--green-dark:#0A5E2C;
--ink:#1B1B18;--ink2:#3A3A34;--muted:#6B6A60;--cream:#F7F3E6;--card:#FFFFFF;--line:#E6DFC8;
--mark:#FFF1BF;--warn-bg:#FFF4D6;--warn-ink:#6A4B00}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--ink:#F3F0E6;--ink2:#D9D5C8;
--muted:#A9A595;--cream:#141410;--card:#1E1E19;--line:#34342C;--green:#5CC184;--green-dark:#8AD7A7;
--mark:#4A3D10;--warn-bg:#3A2F0E;--warn-ink:#FFE08A}}
:root[data-theme="dark"]{--ink:#F3F0E6;--ink2:#D9D5C8;--muted:#A9A595;--cream:#141410;
--card:#1E1E19;--line:#34342C;--green:#5CC184;--green-dark:#8AD7A7;--mark:#4A3D10;
--warn-bg:#3A2F0E;--warn-ink:#FFE08A}
*{box-sizing:border-box}
html{-webkit-text-size-adjust:100%}
body{margin:0;background:var(--cream);color:var(--ink);
font:16px/1.6 system-ui,-apple-system,"Segoe UI",Roboto,"Noto Sans","Noto Sans Devanagari",sans-serif}
header.top{background:var(--haldi);color:#1B1B18;padding:20px 16px 18px}
header.top .wrap{display:flex;align-items:center;gap:12px}
.logo{width:40px;height:40px;border-radius:12px;background:#0E7C3A;color:#FFCC33;display:grid;
place-items:center;font-weight:800;font-size:22px;flex:none}
.brand{font-weight:800;font-size:20px;letter-spacing:.2px}
.brand small{display:block;font-weight:600;font-size:13px;color:#3A3A34}
.wrap{max-width:760px;margin:0 auto}
main{padding:8px 16px 48px}
nav.links{display:flex;gap:16px;flex-wrap:wrap;margin:14px 0 0;font-weight:600;font-size:14px}
nav.links a{color:#0A5E2C}
.draft{background:var(--warn-bg);color:var(--warn-ink);border:1px solid var(--haldi-deep);
border-radius:12px;padding:12px 14px;margin:20px 0 4px;font-weight:700}
h1{font-size:30px;line-height:1.15;margin:24px 0 8px}
h2{font-size:21px;line-height:1.25;margin:34px 0 8px;color:var(--green-dark);
padding-top:6px;border-top:1px solid var(--line)}
h3{font-size:17px;margin:22px 0 6px}
p,li{color:var(--ink2)}
a{color:var(--green);text-underline-offset:2px}
ul,ol{padding-left:22px}
li{margin:4px 0}
blockquote{margin:16px 0;padding:14px 16px;background:var(--card);border-left:5px solid var(--haldi);
border-radius:0 12px 12px 0}
blockquote p{margin:6px 0}
code{font:inherit;background:var(--mark);padding:0 4px;border-radius:4px}
mark.ph{background:var(--mark);color:inherit;padding:0 4px;border-radius:4px;font-weight:600}
.table{overflow-x:auto;margin:14px 0;border:1px solid var(--line);border-radius:12px;background:var(--card)}
table{border-collapse:collapse;width:100%;font-size:14.5px}
th,td{text-align:left;vertical-align:top;padding:9px 11px;border-bottom:1px solid var(--line)}
th{background:var(--haldi);color:#1B1B18;font-weight:700}
tr:last-child td{border-bottom:0}
hr{border:0;border-top:1px solid var(--line);margin:24px 0}
footer{border-top:1px solid var(--line);padding:18px 16px 32px;color:var(--muted);font-size:14px}
@media (max-width:480px){h1{font-size:25px}h2{font-size:19px}table{font-size:13.5px}}
@media print{header.top{background:none}nav.links{display:none}}
"""


def is_note(text: str) -> bool:
    return text.lstrip().startswith("`[Note")


def inline(text: str) -> str:
    out = html.escape(text, quote=False)

    def code(m: re.Match[str]) -> str:
        inner = m.group(1)
        if inner.startswith("[") and inner.endswith("]"):
            return f'<mark class="ph">{inner}</mark>'
        return f"<code>{inner}</code>"

    out = re.sub(r"`([^`]+)`", code, out)
    out = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", out)
    out = re.sub(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])", r"<em>\1</em>", out)
    out = re.sub(r"\[([^\]]+)\]\((https?://[^)\s]+)\)", r'<a href="\2">\1</a>', out)
    # Bare URLs not already inside a tag attribute or link text.
    out = re.sub(
        r'(?<!["=>])(https?://[^\s<)]+[^\s<).,;:])',
        lambda m: f'<a href="{m.group(1)}">{m.group(1)}</a>',
        out,
    )
    return out


def slug(text: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return s or "section"


def render(md: str) -> tuple[str, bool]:
    lines = md.splitlines()
    out: list[str] = []
    draft = False
    i = 0
    n = len(lines)

    def para_until(start: int) -> tuple[str, int]:
        buf = []
        j = start
        while j < n and lines[j].strip() and not re.match(r"^(#|>|\||- |\d+\. |---\s*$)", lines[j]):
            buf.append(lines[j].strip())
            j += 1
        return " ".join(buf), j

    while i < n:
        line = lines[i]
        s = line.strip()
        if not s:
            i += 1
            continue
        if re.match(r"^---\s*$", s):
            out.append("<hr>")
            i += 1
            continue
        m = re.match(r"^(#{1,3})\s+(.*?)(?:\s*\{#([\w-]+)\})?\s*$", s)
        if m:
            level, text, anchor = len(m.group(1)), m.group(2), m.group(3)
            if level == 1:
                out.append(f"<h1>{inline(text)}</h1>")
            else:
                out.append(f'<h{level} id="{anchor or slug(text)}">{inline(text)}</h{level}>')
            i += 1
            continue
        if s.startswith(">"):
            block = []
            while i < n and lines[i].strip().startswith(">"):
                block.append(lines[i].strip()[1:].strip())
                i += 1
            text = " ".join(block)
            if "DRAFT" in text and "lawyer" in text:
                draft = True
                continue
            paras = [p for p in "\n".join(block).split("\n\n")]
            body = "".join(f"<p>{inline(' '.join(p.split()))}</p>" for p in paras if p.strip())
            out.append(f"<blockquote>{body}</blockquote>")
            continue
        if s.startswith("|"):
            rows = []
            while i < n and lines[i].strip().startswith("|"):
                rows.append(lines[i].strip())
                i += 1
            cells = [[c.strip() for c in r.strip("|").split("|")] for r in rows]
            head, body = cells[0], [r for r in cells[2:]]
            t = ["<div class='table'><table><thead><tr>"]
            t += [f"<th>{inline(c)}</th>" for c in head]
            t.append("</tr></thead><tbody>")
            for r in body:
                t.append("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>")
            t.append("</tbody></table></div>")
            out.append("".join(t))
            continue
        if re.match(r"^(- |\d+\. )", s):
            ordered = bool(re.match(r"^\d+\. ", s))
            tag = "ol" if ordered else "ul"
            items: list[tuple[str, list[str]]] = []
            while i < n and lines[i].strip():
                ln = lines[i]
                if re.match(r"^\s{2,}- ", ln) and items:
                    items[-1][1].append(re.sub(r"^\s*- ", "", ln))
                elif re.match(r"^(- |\d+\. )", ln):
                    items.append((re.sub(r"^(- |\d+\. )", "", ln), []))
                elif items:  # continuation line
                    items[-1] = (items[-1][0] + " " + ln.strip(), items[-1][1])
                else:
                    break
                i += 1
            lis = []
            for text, subs in items:
                if is_note(text):
                    continue
                sub = ""
                if subs:
                    sub = "<ul>" + "".join(f"<li>{inline(x)}</li>" for x in subs) + "</ul>"
                lis.append(f"<li>{inline(text)}{sub}</li>")
            if lis:
                out.append(f"<{tag}>{''.join(lis)}</{tag}>")
            continue
        if is_note(s):
            # Skip the whole reviewer note (it may span lines until the closing "]`").
            while i < n and not lines[i].rstrip().endswith("]`"):
                i += 1
            i += 1
            continue
        text, i = para_until(i)
        out.append(f"<p>{inline(text)}</p>")
    return "\n".join(out), draft


def page(title: str, short: str, body: str, draft: bool) -> str:
    banner = (
        '<div class="draft" role="note">DRAFT — must be reviewed by a qualified Indian lawyer '
        "before publishing. Highlighted items are placeholders.</div>"
        if draft
        else ""
    )
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title>
<meta name="description" content="{html.escape(title)} for the Banega household meal-planning app by Kornea.">
<meta name="color-scheme" content="light dark">
<style>{CSS}</style>
</head>
<body>
<header class="top"><div class="wrap">
<div style="display:flex;align-items:center;gap:12px">
<div class="logo" aria-hidden="true">ब</div>
<div class="brand">Banega<small>{html.escape(short)}</small></div>
</div>
<nav class="links" aria-label="Legal pages"><a href="privacy">Privacy Policy</a><a href="terms">Terms of Service</a><a href="privacy#delete-account">Delete your account</a></nav>
</div></header>
<main><div class="wrap">
{banner}
{body}
</div></main>
<footer><div class="wrap">Banega by Kornea · Contact: <a href="mailto:anshul@kornea.in">anshul@kornea.in</a></div></footer>
</body>
</html>
"""


def main() -> None:
    for src, dst, title, short in PAGES:
        body, draft = render((LEGAL / src).read_text(encoding="utf-8"))
        (HERE / dst).write_text(page(title, short, body, draft), encoding="utf-8", newline="\n")
        print(f"wrote {HERE / dst}")


if __name__ == "__main__":
    main()

"""Generate the local HTML audit and Markdown companion from curated audit data.

Run from any directory: python3 /path/to/generate_active_session_audit.py
Uses only the Python standard library. Does not read recovery logs or app data.
"""

import base64
import html
import json
import mimetypes
from pathlib import Path
from urllib.parse import quote


HERE = Path(__file__).resolve().parent
EVIDENCE = HERE.parent / "evidence/2026-09-07-active-session-vs-t3"
STEM = "2026-09-07-active-session-vs-t3-code"
DATA = json.loads((HERE / "active-session-audit.json").read_text())
COVERAGE = json.loads((HERE / "active-session-audit-coverage.json").read_text())
PROBE = (EVIDENCE / "verify-warm-persistence.output.txt").read_text()


def escape(value):
    return html.escape(str(value), quote=True)


def source(reference):
    scope, path, line = reference.split(":")
    repo, commit = ("NextStep-AI-inc/10x", DATA["baseline"]) if scope == "10x" else ("pingdotgg/t3code", DATA["t3_source"])
    url = f"https://github.com/{repo}/blob/{commit}/{quote(path, safe='/')}#L{line}"
    return f"{scope} / {Path(path).name}:{line}", url


def sources(references):
    return '<div class="refs">' + "".join(
        f'<a href="{escape(url)}">{escape(label)}</a>'
        for label, url in map(source, references)) + "</div>"


def paragraph(value, class_name=""):
    return f'<p class="{class_name}">{escape(value)}</p>'


def unordered(values):
    return "<ul>" + "".join(f"<li>{escape(value)}</li>" for value in values) + "</ul>"


def section(identifier, title, content):
    return f'<section id="{identifier}"><h2>{escape(title)}</h2>{content}</section>'


def table(headers, rows):
    return ('<div class="table-scroll"><table><thead><tr>'
            + "".join(f'<th scope="col">{escape(value)}</th>' for value in headers)
            + "</tr></thead><tbody>"
            + "".join("<tr>" + "".join(f"<td>{escape(value)}</td>" for value in row) + "</tr>" for row in rows)
            + "</tbody></table></div>")


def figure(item):
    images = []
    for side in ("left", "right"):
        path = EVIDENCE / item[side]
        mime = mimetypes.guess_type(path)[0]
        uri = f"data:{mime};base64," + base64.b64encode(path.read_bytes()).decode()
        images.append(f'<div class="shot"><p class="image-label">{escape(item[side + "_label"])}</p>'
                      f'<img src="{uri}" alt="{escape(item["title"] + ": " + item[side + "_label"])}">'
                      f'<a class="original" href="../evidence/2026-09-07-active-session-vs-t3/{escape(path.name)}">Open image file</a></div>')
    return (f'<figure><figcaption><h3>{escape(item["title"])}</h3>{paragraph(item["caption"])}</figcaption>'
            + '<div class="image-pair">' + "".join(images) + "</div></figure>")


def finding(item):
    identifier = item["id"].lower()
    title = (f'<div class="finding-title"><span class="priority {item["priority"].lower()}">{item["priority"]}</span>'
             f'<h3>{escape(item["title"])}</h3><span class="finding-id">{item["id"]}</span></div>')
    body = paragraph(item.get("basis", "Source-derived improvement; see verification limits"), "basis")
    for key, label in (("behavior", "Observed behavior and mechanism"), ("impact", "Why it matters"),
                       ("recommendation", "Proposed change"), ("acceptance", "Acceptance criteria")):
        if key in item:
            body += f'<div class="finding-part"><h4>{label}</h4>{paragraph(item[key])}</div>'
    if item.get("evidence"):
        body += paragraph(item["evidence"], "evidence-note")
    return f'<article class="finding" id="{identifier}">{title}{body}{sources(item["refs"])}</article>'


def prose_pairs(items):
    return "".join(f'<article class="prose-item"><h3>{escape(title)}</h3>{paragraph(body)}</article>' for title, body in items)


CSS = """
:root{color-scheme:light dark;--canvas:#FFFFFF;--ink:#0C0C0B;--muted:#666662;--line:#E5E5E1;--paper:#F7F7F5;--accent:#00A7C4;--link:#007C92;--danger:#A62112;--danger-bg:#FFF0ED;--attention:#705500;--attention-bg:#FFF6CD;--image-ground:#FFFFFF;--display:'Outfit',-apple-system,BlinkMacSystemFont,'Helvetica Neue',sans-serif;--body:-apple-system,BlinkMacSystemFont,'SF Pro Text','Helvetica Neue',Arial,sans-serif;--mono:ui-monospace,'SF Mono',Menlo,Consolas,monospace}
@media(prefers-color-scheme:dark){:root:not([data-theme="light"]){--canvas:#101414;--ink:#F1F4F3;--muted:#B0BAB8;--line:#33403D;--paper:#19211F;--accent:#3AC3DA;--link:#66D4E5;--danger:#FFACA1;--danger-bg:#3F211D;--attention:#FFDC71;--attention-bg:#342F1C}}
:root[data-theme="dark"]{--canvas:#101414;--ink:#F1F4F3;--muted:#B0BAB8;--line:#33403D;--paper:#19211F;--accent:#3AC3DA;--link:#66D4E5;--danger:#FFACA1;--danger-bg:#3F211D;--attention:#FFDC71;--attention-bg:#342F1C}
*{box-sizing:border-box}body{margin:0;background:var(--canvas);color:var(--ink);font-family:var(--body);font-size:16px;line-height:1.62;-webkit-font-smoothing:antialiased}main{max-width:1200px;margin:auto;padding:40px 36px 80px}p{margin:0;max-width:70ch}a{color:var(--link);text-underline-offset:.2em}a:hover{text-decoration-thickness:2px}a:focus-visible,summary:focus-visible{outline:2px solid var(--link);outline-offset:4px}h1,h2,h3,h4{margin:0;text-wrap:balance}h1,h2{font-family:var(--display);font-weight:500;line-height:1.1}h1{font-size:clamp(30px,4vw,46px);letter-spacing:-.025em}h2{font-size:29px}h3{font-size:19px;line-height:1.35}h4{font-family:var(--mono);font-size:11px;line-height:1.4;font-weight:500;text-transform:uppercase;letter-spacing:.06em;color:var(--muted)}header{display:grid;gap:16px;max-width:850px}.eyebrow,.basis,.image-label,.finding-id,.original{font-family:var(--mono);font-size:11px;line-height:1.5;color:var(--muted)}.eyebrow{letter-spacing:.08em;text-transform:uppercase}.lede{font-size:20px;line-height:1.5;max-width:65ch}.scope{font-size:13px;color:var(--muted)}.recommendation{padding:14px 18px;border-left:3px solid var(--accent);background:var(--paper);max-width:75ch}nav{display:flex;flex-wrap:wrap;gap:8px 18px;font-family:var(--mono);font-size:12px;padding:12px 0 8px}.lead-evidence{margin-top:30px}section{display:grid;gap:24px;margin-top:58px;scroll-margin-top:24px}.finding{display:grid;gap:17px;padding:24px 0;border-top:1px solid var(--line);max-width:880px}.finding-title{display:flex;flex-wrap:wrap;align-items:baseline;gap:10px}.finding-title h3{flex:1 1 420px}.finding-id{flex:0 0 auto}.priority{font-family:var(--mono);font-size:12px;padding:3px 7px;line-height:1.3;font-variant-numeric:tabular-nums;color:var(--muted);background:var(--paper)}.p0{color:var(--danger);background:var(--danger-bg)}.p1{color:var(--attention);background:var(--attention-bg)}.finding-part{display:grid;gap:6px}.evidence-note{font-size:13px;color:var(--muted);padding:12px 14px;background:var(--paper)}.refs{display:flex;flex-wrap:wrap;gap:5px 16px}.refs a{font-family:var(--mono);font-size:11px;overflow-wrap:anywhere}.table-scroll{overflow-x:auto;max-width:100%;border-bottom:1px solid var(--line)}table{border-collapse:collapse;width:100%;min-width:740px;font-size:14px;line-height:1.5}th{text-align:left;color:var(--muted);font-family:var(--mono);font-size:11px;letter-spacing:.04em;text-transform:uppercase;font-weight:500}th,td{padding:13px 16px 13px 0;border-top:1px solid var(--line);vertical-align:top}td:first-child{font-weight:600;min-width:130px}th:first-child{width:16%}td{overflow-wrap:anywhere}figure{display:grid;gap:14px;margin:0}figcaption{display:grid;gap:8px}figcaption p{font-size:14px;color:var(--muted);max-width:85ch}.image-pair{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:20px;align-items:start}.shot{display:grid;gap:8px;min-width:0}.shot img{display:block;width:100%;height:auto;max-height:550px;object-fit:contain;object-position:top;background:var(--image-ground);border:1px solid var(--line)}.original{color:var(--link);width:fit-content}.gallery{display:grid;gap:42px}.prose-item{display:grid;gap:8px;max-width:820px}.prose-item p{font-size:15px}.verification{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:28px}.verification h3{font-family:var(--mono);font-size:12px;text-transform:uppercase;letter-spacing:.04em;border-bottom:2px solid var(--accent);padding-bottom:10px}.verification ul{font-size:14px}.verification li{margin:12px 0}ul,ol{margin:0;padding-left:22px}li+li{margin-top:10px}ol.roadmap{display:grid;gap:20px;max-width:880px}ol.roadmap li{padding-left:8px}ol.roadmap li::marker{font-family:var(--mono);color:var(--link);font-variant-numeric:tabular-nums}ol.roadmap h3{font-size:18px}ol.roadmap p{margin-top:6px;font-size:15px}pre{max-width:100%;margin:0;padding:18px;background:var(--paper);overflow-x:auto;font-family:var(--mono);font-size:12px;line-height:1.6;color:var(--ink)}code{font-family:var(--mono);font-size:.86em;overflow-wrap:anywhere}.appendix table{font-size:12px}.appendix td:first-child{font-family:var(--mono);min-width:86px}.appendix th:first-child{width:10%}.appendix td:nth-child(2){width:17%}footer{display:grid;gap:10px;margin-top:60px;padding-top:20px;border-top:1px solid var(--line);font-size:12px;color:var(--muted)}
@media(max-width:850px){main{padding:28px 20px 60px}.verification{grid-template-columns:1fr}.image-pair{grid-template-columns:1fr}.finding-title h3{flex-basis:75%}section{margin-top:42px}.lede{font-size:18px}h2{font-size:26px}}
@media print{main{padding:0;max-width:none}nav,.original{display:none}.finding,.prose-item{break-inside:avoid}.image-pair{grid-template-columns:1fr 1fr}.shot img{max-height:360px}body{font-size:11pt}section{margin-top:24px}h1{font-size:28pt}h2{font-size:20pt}.verification{grid-template-columns:1fr}a{color:var(--ink)}table{min-width:0}pre{white-space:pre-wrap;overflow-wrap:anywhere}}
"""


def build_html():
    nav = "".join(f'<a href="#{identifier}">{title}</a>' for identifier, title in (
        ("priorities", "First fixes"), ("comparison", "Comparison"), ("improvements", "Improvements"),
        ("evidence", "Visual evidence"), ("roadmap", "Implementation order"), ("limits", "Verification limits"), ("index", "Finding index")))
    parts = ["<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
             f'<title>{escape(DATA["title"])}</title><link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Outfit:wght@500&display=swap">',
             f"<style>{CSS}</style></head><body><main><header>",
             paragraph(f'Active session audit · {DATA["date"]} · 10x 59a4ae8 / T3 0.0.39', "eyebrow"),
             f'<h1>{escape(DATA["title"])}</h1>', paragraph(DATA["headline"], "lede"),
             paragraph(DATA["recommendation"], "recommendation"), paragraph(DATA["scope_note"], "scope"),
             f"<nav aria-label=\"Report sections\">{nav}</nav></header>",
             '<div class="lead-evidence">' + figure(DATA["gallery"][0]) + "</div>",
             section("priorities", "Six fixes before more workspace chrome", "".join(map(finding, DATA["findings"]))),
             section("comparison", "Where the experience differs", table(["Area", "10x", "T3 Code", "Assessment"], DATA["comparison"])),
             section("improvements", "The product improvements worth making", "".join(map(finding, DATA["improvements"]))),
             section("keep", "Keep what gives 10x its identity", prose_pairs(DATA["strengths"])),
             section("optional", "Choose the workspace scope deliberately", prose_pairs(DATA["decisions"]) + unordered(DATA["deferred"])),
             section("corrections", "Claims corrected during synthesis", prose_pairs(DATA["corrections"])),
             section("evidence", "Visual evidence and its limits", paragraph(DATA["evidence_note"], "evidence-note")
                     + '<div class="gallery">' + "".join(map(figure, DATA["gallery"][1:])) + "</div>"),
             section("probe", "The current persistence check", paragraph("Four RPC cases, disposable data, zero model calls. This check distinguishes an ephemeral new session from a failed existing-session open.")
                     + f"<pre>{escape(PROBE)}</pre>"
                     + '<p><a href="../evidence/2026-09-07-active-session-vs-t3/verify-warm-persistence.py">Runnable probe</a> · <a href="../evidence/2026-09-07-active-session-vs-t3/manifest.json">Image provenance manifest</a></p>'),
             section("roadmap", "Implementation order", '<ol class="roadmap">' + "".join(
                 f'<li><h3>{escape(title)}</h3>{paragraph(body)}</li>' for title, body in DATA["roadmap"]) + "</ol>"),
             section("method", "Method and boundaries", prose_pairs(DATA["method"])),
             section("limits", "Verification and next tests", '<div class="verification">' + "".join(
                 f'<div><h3>{label}</h3>{unordered(DATA[key])}</div>' for label, key in (
                     ("Verified", "verified"), ("Not verified", "not_verified"), ("For you to test", "for_you"))) + "</div>"),
             section("index", "Complete finding disposition index", paragraph(f'{len(COVERAGE)} recovered observations are accounted for below. IDs preserve traceability across duplicates; they are not counts of distinct confirmed bugs. Source-derived candidates and open questions still need the specified UI checks.')
                     + '<div class="appendix">' + table(["Original ID", "Report group", "Disposition", "Observation"], (
                         [row["id"], row["group"], row["disposition"], row["title"]] for row in COVERAGE)) + "</div>"),
             f'<footer><p>Audit only · fixed source baseline · local review deliverable</p><p><a href="{STEM}.md">Markdown companion</a> · <a href="{STEM}-plan.md">Completion plan</a> · <a href="active-session-audit.json">Curated report data</a></p></footer>',
             "</main></body></html>"]
    (HERE / f"{STEM}.html").write_text("\n".join(parts))


def md_table(headers, rows):
    clean = lambda value: str(value).replace("|", "\\|").replace("\n", " ")
    return "\n".join("| " + " | ".join(map(clean, row)) + " |" for row in [headers, ["---"] * len(headers), *rows])


def build_markdown():
    out = [f'# {DATA["title"]}', f'**{DATA["date"]}. Audit only.** [Open the HTML report]({STEM}.html).',
           DATA["headline"], DATA["recommendation"], DATA["scope_note"], DATA["evidence_note"]]
    for key, title in (("findings", "Six fixes before more workspace chrome"), ("improvements", "Product improvements")):
        out.append(f"## {title}")
        for item in DATA[key]:
            out.extend([f'### {item["priority"]} {item["id"]}: {item["title"]}',
                        f'**Evidence class:** {item.get("basis", "Source-derived improvement; see verification limits")}.'])
            for field, label in (("behavior", "Behavior"), ("impact", "Impact"), ("recommendation", "Proposed change"), ("acceptance", "Acceptance criteria"), ("evidence", "Evidence limits")):
                if item.get(field): out.append(f'**{label}:** {item[field]}')
            out.append("Sources: " + ", ".join(f"[{label}]({url})" for label, url in map(source, item["refs"])))
    out.extend(["## Comparison", md_table(["Area", "10x", "T3 Code", "Assessment"], DATA["comparison"])])
    for key, title in (("strengths", "What to keep"), ("decisions", "Product scope choices"), ("corrections", "Corrected claims")):
        out.append(f"## {title}")
        for heading, body in DATA[key]:out.extend([f"### {heading}", body])
    out.extend(["## Deferred scope", "\n".join(f"- {item}" for item in DATA["deferred"]), "## Visual evidence"])
    for item in DATA["gallery"]:
        out.extend([f'### {item["title"]}', item["caption"], md_table([item["left_label"], item["right_label"]], [[
            f'![{item["left_label"]}](../evidence/2026-09-07-active-session-vs-t3/{item["left"]})',
            f'![{item["right_label"]}](../evidence/2026-09-07-active-session-vs-t3/{item["right"]})']])])
    out.extend(["## Current persistence probe", "```text\n" + PROBE.rstrip() + "\n```",
                "[Runnable probe](../evidence/2026-09-07-active-session-vs-t3/verify-warm-persistence.py). [Image manifest](../evidence/2026-09-07-active-session-vs-t3/manifest.json).",
                "## Proposed implementation order", "\n".join(f"{i}. **{title}.** {body}" for i, (title, body) in enumerate(DATA["roadmap"], 1))])
    out.append("## Method")
    for title, body in DATA["method"]:out.extend([f"### {title}", body])
    for title, key in (("Verified", "verified"), ("Not verified", "not_verified"), ("For you to test", "for_you")):
        out.extend([f"## {title}", "\n".join(f"- {item}" for item in DATA[key])])
    out.extend([f"## Finding disposition index ({len(COVERAGE)} observations)",
                "IDs preserve traceability across duplicates. These are not counts of distinct confirmed bugs.",
                md_table(["Original ID", "Report group", "Disposition", "Observation"], [[r["id"], r["group"], r["disposition"], r["title"]] for r in COVERAGE])])
    (HERE / f"{STEM}.md").write_text("\n\n".join(out) + "\n")


if __name__ == "__main__":
    build_html()
    build_markdown()
    for extension in ("html", "md"):
        path = HERE / f"{STEM}.{extension}"
        print(f"Wrote {path.name}: {path.stat().st_size:,} bytes")

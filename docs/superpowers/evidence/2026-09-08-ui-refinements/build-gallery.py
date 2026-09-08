#!/usr/bin/env python3
"""Build the self-contained native evidence gallery after acceptance captures exist."""
from pathlib import Path
from html import escape
import base64
import json
import re

root = Path(__file__).resolve().parent
previous = root.parent / "2026-09-08-audit-integration/progress-gallery.html"
style = re.search(r"<style>(.*?)</style>", previous.read_text(), re.S).group(1)
manifest = json.loads((root / "native-final-build.json").read_text())

cards = [
    ("activity", "An animated working signal", "The composer and quiet transcript use three moving bars. The header keeps its readable Working status.", "Look at the header, then the small animated bars beside the composer controls.", [
        ("native-final-working-a.jpg", "Running session: header status and compact activity"),
    ]),
    ("warnings", "Warnings stay inside a flyout", "Independent warnings share a small warning control. The panel fits its content, and the composer keeps the same height as warnings appear.", "The attachment and model warnings are separate entries. The panel follows the warning control's outline.", [
        ("native-final-dual-warning.jpg", "Two independent warnings in the fitted panel"),
        ("native-final-no-warning.jpg", "The same composer with no warnings"),
    ]),
    ("follow-up", "Messages keep their send mode", "Follow-up messages have a branch symbol, cyan accent and soft surface. Steer messages use an arrow and a yellow accent. Known modes remain visible after delivery and reopening.", "Compare the two queued messages, then their persisted transcript bubbles after reopening the app.", [
        ("native-final-queued-modes.jpg", "Follow-up and steer waiting for delivery"),
        ("native-final-reopened-modes.jpg", "The same messages after app relaunch"),
        ("native-final-send-action.jpg", "The app-owned send-action panel at minimum width"),
    ]),
    ("diff", "Less repetition in diffs", "Colored addition and removal totals appear once in the tool header. A single-file card uses that file title once; multi-file details keep one aligned row per file.", "Check the colored header totals, neutral per-file totals, and the shared row for Wrap or Scroll and Copy patch.", [
        ("native-final-multi-diff.jpg", "Expanded multi-file diff in the Release build"),
        ("native-single-diff-minimum.jpg", "Single-file diff with its repeated file title removed"),
    ]),
    ("popups", "Panels fit the window", "Model, project, context, warning and send-action controls own their panels. They share placement rules that clamp to the window and choose the available opening direction.", "At the minimum window size, the model list scrolls, context stays within the window, and each outline connects to its control.", [
        ("native-final-model-minimum.jpg", "Model panel at minimum window size"),
        ("native-final-context-minimum.jpg", "Context panel at minimum window size"),
        ("native-project-minimum.jpg", "Project panel at minimum window size"),
    ]),
]

def picture(filename, caption):
    path = root / filename
    assert path.is_file(), filename
    mime = "image/jpeg" if path.suffix == ".jpg" else "image/png"
    src = f"data:{mime};base64,{base64.b64encode(path.read_bytes()).decode()}"
    title = escape(caption, quote=True)
    return f'<button class="image-button" type="button" data-full="{src}" data-alt="{title}"><img loading="lazy" src="{src}" alt="{title}"><span class="zoom">Open full size</span></button><p class="caption">{escape(caption)}</p>'

parts = []
for index, (key, title, change, look, pictures) in enumerate(cards, 1):
    media = "".join(picture(*item) for item in pictures)
    parts.append(f'<article class="evidence-card" id="{key}"><div class="evidence-copy"><span class="eyebrow">Adjustment {index:02}</span><h2>{escape(title)}</h2><p>{escape(change)}</p><p><strong>Look for:</strong> {escape(look)}</p></div>{media}</article>')
nav = "".join(f'<a href="#{key}">{escape(title)}</a>' for key, title, *_ in cards)
html = f"""<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>10x UI refinements — native evidence</title><style>{style}
.caption{{padding:0 24px 16px}}.evidence-card .image-button{{margin-top:20px}}.evidence-copy p{{font-size:15px}}.evidence-grid{{margin-top:28px}}</style></head><body><main>
<header class="hero"><div><p class="kicker">10x / requested UI adjustments</p><h1>Your five UI adjustments</h1><p class="dek">Real screenshots from the isolated macOS Release build, with a guide to each change.</p></div><div class="stamp">Build under test<strong>{manifest["sourceCommit"][:12]}</strong><span>Native macOS · arm64</span></div></header>
<nav class="gallery-nav" aria-label="Jump to an adjustment">{nav}</nav><section class="evidence-grid">{"".join(parts)}</section>
<section class="section proof"><div class="panel"><h2>Native checks</h2><p>Clicked the actual controls for model and project selection, context details, warnings, send mode, copy patch and file navigation. Queued follow-up and steer messages were delivered and checked again after quitting and reopening the app. Keyboard selection, Escape and composer focus return were exercised.</p></div><div class="panel"><h2>Limits</h2><p>The acceptance session uses a local RPC fixture, so no external model work is represented here. Older messages without recorded mode stay standard. Identical overlapping payloads sent with conflicting modes also stay unannotated after delivery because OMP supplies no originating queue ID.</p></div></section>
<footer class="footer">Source: {escape(manifest["branch"])} at {manifest["sourceCommit"][:12]}. No GitHub merge or deployment. The earlier live CJK input gate is unchanged. Full verification details are in the adjacent README and verification.json.</footer></main>
<div class="modal" role="dialog" aria-modal="true" aria-label="Full screenshot"><div class="modal-inner"><button class="close" type="button">Close</button><img alt=""></div></div>
<script>const modal=document.querySelector('.modal'),img=modal.querySelector('img'),closeButton=modal.querySelector('.close');let opener;function close(){{modal.classList.remove('open');img.src='';opener?.focus()}}document.querySelectorAll('.image-button').forEach(button=>button.addEventListener('click',()=>{{opener=button;img.src=button.dataset.full;img.alt=button.dataset.alt;modal.classList.add('open');closeButton.focus()}}));closeButton.addEventListener('click',close);modal.addEventListener('click',event=>{{if(event.target===modal)close()}});document.addEventListener('keydown',event=>{{if(!modal.classList.contains('open'))return;if(event.key==='Escape')close();if(event.key==='Tab'){{event.preventDefault();closeButton.focus()}}}});</script></body></html>"""
(root / "progress-gallery.html").write_text(html)
print(f"Wrote {len(cards)} sections with {sum(len(card[-1]) for card in cards)} native captures.")

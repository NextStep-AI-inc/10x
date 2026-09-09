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
manifest = json.loads((root / "native-density-build.json").read_text())

cards = [
    ("send-control", "Two compact choices", "Steer and Follow up now use two single-line rows. The explanation is available on hover, and keyboard selection still returns focus to the composer.", "The menu is 164 points wide with two 28-point rows, down from 272 by 104 points.", [
        ("native-density-send-minimum-light.jpg", "Compact send choices in light mode, minimum window size"),
        ("native-density-send-minimum-dark.jpg", "Compact send choices in dark mode, minimum window size"),
    ]),
    ("usage-rings", "Room around the usage rings", "The usage rings sit in their own strip below the composer. Model, context and send controls retain their space inside the box.", "The ring strip stays below the composer while the model panel opens above its control.", [
        ("native-density-model-minimum-light.jpg", "Separate usage rings and model controls in light mode"),
        ("native-density-model-minimum-dark.jpg", "Separate usage rings and model controls in dark mode"),
    ]),
    ("follow-up", "The same user-message surface", "Follow-up and steer messages use the same black surface as regular user messages in light mode, and the same white surface in dark mode. Their symbols and accent edges remain distinct.", "Compare the two delivered messages in both themes. The final capture shows the same treatment while messages are queued.", [
        ("native-density-delivered-light.jpg", "Delivered follow-up and steer messages in light mode"),
        ("native-density-delivered-dark.jpg", "Delivered follow-up and steer messages in dark mode"),
        ("native-density-queued-dark.jpg", "Regular, follow-up and steer messages share the white dark-mode surface"),
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
nav = "".join(f'<a href="#{key}">{escape(title)}</a>' for key, title, *_ in cards) + '<a href="progress-gallery-first-refinement.html">Earlier five adjustments</a><a href="../2026-09-08-audit-integration/progress-gallery.html">Original audit gallery</a>'
html = f"""<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>10x UI refinements — native evidence</title><style>{style}
.caption{{padding:0 24px 16px}}.evidence-card .image-button{{margin-top:20px}}.evidence-copy p{{font-size:15px}}.evidence-grid{{margin-top:28px}}</style></head><body><main>
<header class="hero"><div><p class="kicker">10x / density and appearance</p><h1>Compact controls, consistent messages</h1><p class="dek">The latest revision, shown in the real macOS Release build in light and dark mode.</p></div><div class="stamp">Build under test<strong>{manifest["sourceCommit"][:12]}</strong><span>Native macOS · arm64</span></div></header>
<nav class="gallery-nav" aria-label="Jump to an adjustment">{nav}</nav><section class="evidence-grid">{"".join(parts)}</section>
<section class="section proof"><div class="panel"><h2>Native checks</h2><p>Checked the send and model panels at minimum size in both themes, selected both send modes, sent and delivered queued messages, and opened a usage ring. Send-menu Escape and composer focus return passed. The original macOS Auto appearance setting was restored.</p></div><div class="panel"><h2>Limits</h2><p>The session uses a local RPC fixture. Usage details opened and closed with their Close button; Escape did not dismiss that separate panel. Full-suite timing and baseline screenshot failures remain recorded in the evidence report. The earlier gallery retains the first five adjustments.</p></div></section>
<footer class="footer">Source: {escape(manifest["branch"])} at {manifest["sourceCommit"][:12]}. PR #46 remains draft. Full results and remaining gaps are in README.md and density-verification.json.</footer></main>
<div class="modal" role="dialog" aria-modal="true" aria-label="Full screenshot"><div class="modal-inner"><button class="close" type="button">Close</button><img alt=""></div></div>
<script>const modal=document.querySelector('.modal'),img=modal.querySelector('img'),closeButton=modal.querySelector('.close');let opener;function close(){{modal.classList.remove('open');img.src='';opener?.focus()}}document.querySelectorAll('.image-button').forEach(button=>button.addEventListener('click',()=>{{opener=button;img.src=button.dataset.full;img.alt=button.dataset.alt;modal.classList.add('open');closeButton.focus()}}));closeButton.addEventListener('click',close);modal.addEventListener('click',event=>{{if(event.target===modal)close()}});document.addEventListener('keydown',event=>{{if(!modal.classList.contains('open'))return;if(event.key==='Escape')close();if(event.key==='Tab'){{event.preventDefault();closeButton.focus()}}}});</script></body></html>"""
(root / "progress-gallery.html").write_text(html)
print(f"Wrote {len(cards)} sections with {sum(len(card[-1]) for card in cards)} native captures.")

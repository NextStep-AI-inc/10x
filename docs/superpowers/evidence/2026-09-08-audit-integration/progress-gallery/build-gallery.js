const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const pairDir = path.join(root, 'combined-first-run');
const mime = (file) => file.endsWith('.jpg') ? 'image/jpeg' : 'image/png';
const data = (file) => `data:${mime(file)};base64,${fs.readFileSync(file).toString('base64')}`;
const esc = (text) => text.replace(/[&<>"']/g, (c) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

const pairs = [
  ['active-session-header.png', 'active-session-header.actual.png', 'Active session header',
    'The header now shows the shared session activity state. Long branch and folder names shorten to leave room for it.',
    'You can see that a session is working while reading an older part of the conversation.',
    'The blue dot and Working label to the right of the project metadata.'],
  ['composer-stop-control.png', 'composer-stop-control.actual.png', 'Composer controls',
    'The composer now shows the same Working state as the header, beside the context information.',
    'Activity stays visible where you type a follow-up or stop a run.',
    'Working appears after Context unavailable. The square Stop button was already present in the before image.'],
  ['developer-tool-flow.png', 'developer-tool-flow.actual.png', 'Developer tool flow',
    'The diff filename opens the preferred editor. Running commands show their latest ten output lines.',
    'You can open the exact file under review and see recent command progress without expanding the full output.',
    'The TranscriptView.swift link above the diff. Farther down, output changes from test groups 1–10 to 5–14.'],
  ['continuous-settings.png', 'continuous-settings.actual.png', 'Continuous settings',
    'This audit added the Global OMP defaults scope label. The OMP/10x navigation layout was already on main.',
    'The label clarifies which configuration you are editing before changing runtime or approval defaults.',
    'Global OMP defaults immediately above the profile path. The older reference also predates the settings layout change.'],
];
const native = [
  ['native-diff-review.jpg', 'Changed file review',
    'Completed turns list the files reported by edit and write tools. Each path reaches its matching diff, whose file link opens the chosen editor.',
    'Review stays next to the conversation, including when a tool edits several files.',
    'Tool-reported files (2) below the completed turn and the expanded integration-beta.txt diff. Shell-written files are outside this list’s stated scope.'],
  ['native-cold-route-draft-a.jpg', 'Drafts survive relaunch',
    'Unsent text and attached images survive quitting and reopening the app. Each session keeps a separate draft, and the last session reopens.',
    'You can switch sessions or close the app without losing an unsent prompt or moving it into the wrong conversation.',
    'INTEGRATION A UNSENT and the context.png attachment in the composer after a full quit and relaunch.'],
  ['native-unconfirmed-recovered.jpg', 'Unconfirmed send recovery',
    'A send without confirmation restores its draft, image, and a recovery notice after restart. It is not automatically submitted again.',
    'This avoids silently duplicating a prompt when delivery is uncertain.',
    'The previous-send warning above the recovered text and image. The recorded runtime trace contains exactly one submitted prompt.'],
  ['native-dual-warnings.jpg', 'Independent warnings',
    'Attachment and model-loading failures appear separately. Resolving the attachment problem leaves the model warning visible.',
    'Each problem keeps its own explanation, and a rejected file does not remove a valid attachment.',
    'Both warnings above the composer, with context.png still attached.'],
  ['native-queue-count-one.jpg', 'Queued follow-up',
    'Accepted follow-ups update the queue count. The count clears as the queued message is consumed.',
    'You can confirm that a message is waiting and recognize when it has been delivered.',
    'The count of 1 near the composer and the queued-message receipt. This capture also retains the raw background notices recorded as a follow-up concern.'],
  ['native-compaction-failure.jpg', 'Compaction failure state',
    'The context control offers compaction with visible progress and a recoverable error when it fails.',
    'The result is explicit, with a way to retry after failure or stop a pending operation.',
    'The compaction error beside the context controls. This screenshot shows a controlled failure; progress and Stop were checked separately.'],
  ['native-global-scope.jpg', 'Global OMP scope',
    'Settings explicitly labels the global OMP defaults and the profile being edited.',
    'The scope is clear before you change approval defaults. Project settings and tool-specific rules can override those defaults.',
    'Global OMP defaults and the profile path beneath the OMP/10x navigation. No policy value was changed during this check.'],
];

const explanationMarkup = (change, why, look) => `<dl class="change-notes">
  <div><dt>What changed</dt><dd>${esc(change)}</dd></div>
  <div><dt>Why it matters</dt><dd>${esc(why)}</dd></div>
  <div><dt>Look for</dt><dd>${esc(look)}</dd></div>
</dl>`;

const pairMarkup = pairs.map(([before, after, title, change, why, look], i) => `
  <article class="pair-card" id="change-${i + 1}">
    <div class="card-head"><div><span class="eyebrow">Rendered snapshot ${String(i + 1).padStart(2, '0')}</span><h3>${esc(title)}</h3></div><span class="tag blue">Before / after</span></div>
    ${explanationMarkup(change, why, look)}
    <div class="compare" aria-label="${esc(title)} before and after comparison.">
      <button class="snapshot-view" type="button" data-full="${data(path.join(pairDir, before))}" data-alt="${esc(title)} before snapshot"><span>Before · Open larger</span><img src="${data(path.join(pairDir, before))}" alt="${esc(title)} before snapshot"></button>
      <button class="snapshot-view" type="button" data-full="${data(path.join(pairDir, after))}" data-alt="${esc(title)} after snapshot"><span>After · Open larger</span><img src="${data(path.join(pairDir, after))}" alt="${esc(title)} after snapshot"></button>
    </div>
    <button class="text-button compare-toggle" type="button">Show after only</button>
  </article>`).join('');

const nativeMarkup = native.map(([file, title, change, why, look], i) => `
  <article class="evidence-card" id="native-${i + 1}">
    <div class="evidence-copy"><div class="card-head"><h3>${esc(title)}</h3><span class="tag green">Local Release build</span></div>${explanationMarkup(change, why, look)}</div>
    <button class="image-button" type="button" data-full="${data(path.join(root, file))}" data-alt="${esc(title)} screenshot"><img src="${data(path.join(root, file))}" alt="${esc(title)} screenshot"><span class="zoom">Open larger</span></button>
  </article>`).join('');

const jumpLinks = pairs.map((item, i) => `<a href="#change-${i + 1}">${esc(item[2])}</a>`)
  .concat(native.map((item, i) => `<a href="#native-${i + 1}">${esc(item[1])}</a>`)).join('');

const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>10x integration progress gallery</title>
<style>
:root{--ink:#17212b;--muted:#65727d;--line:#dce4e8;--paper:#f7faf9;--card:#fff;--blue:#326b78;--blue-soft:#e6f0f1;--green:#3e7259;--green-soft:#e5f1e9;--amber:#8b5c24;--amber-soft:#fff2dc;--shadow:0 12px 32px #24343d12}*{box-sizing:border-box}body{margin:0;color:var(--ink);background:radial-gradient(circle at 92% 0,#e7f1f0 0,transparent 31rem),var(--paper);font:15px/1.5 ui-sans-serif,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}main{max-width:1320px;margin:auto;padding:46px 24px 80px}.hero{display:flex;justify-content:space-between;gap:32px;align-items:end;margin-bottom:34px}.kicker,.eyebrow{color:var(--blue);font-size:11px;font-weight:760;letter-spacing:.12em;text-transform:uppercase}.kicker{margin:0 0 10px}.eyebrow{font-size:10px;color:#82909a}h1{font-size:clamp(35px,6vw,64px);line-height:1.02;letter-spacing:-.055em;max-width:690px;margin:0 0 16px}h2{font-size:24px;letter-spacing:-.03em;margin:0 0 6px}h3{font-size:22px;line-height:1.18;letter-spacing:-.02em;margin:4px 0 0}.dek{font-size:17px;color:var(--muted);max-width:670px;margin:0}.stamp{min-width:178px;padding:14px 16px;border:1px solid var(--line);border-radius:14px;background:#ffffffaa;color:var(--muted);font-size:12px}.stamp strong{display:block;color:var(--ink);font-size:14px;margin-top:2px}.stats{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;margin-bottom:48px}.stat{padding:18px 18px 16px;border:1px solid var(--line);border-radius:14px;background:var(--card);box-shadow:var(--shadow)}.stat strong{display:block;font-size:30px;line-height:1;color:var(--blue);letter-spacing:-.05em}.stat span{display:block;color:var(--muted);font-size:12px;margin-top:8px}.section{margin-top:48px}.section-intro{display:flex;justify-content:space-between;gap:20px;align-items:end;margin-bottom:18px}.section-intro p{max-width:540px;color:var(--muted);margin:0}.grid{display:grid;grid-template-columns:minmax(0,1fr);gap:32px}.pair-card,.evidence-card{border:1px solid var(--line);border-radius:16px;background:var(--card);box-shadow:var(--shadow);overflow:hidden}.pair-card{padding:24px}.card-head{display:flex;flex-wrap:wrap;align-items:start;justify-content:space-between;gap:12px}.pair-card p,.evidence-card p{color:var(--muted);font-size:13px;margin:8px 0 15px}.tag{display:inline-flex;align-items:center;white-space:nowrap;border-radius:99px;padding:4px 8px;font-size:10px;font-weight:760;letter-spacing:.04em}.tag.blue{color:var(--blue);background:var(--blue-soft)}.tag.green{color:var(--green);background:var(--green-soft)}.tag.amber{color:var(--amber);background:var(--amber-soft)}.compare{display:grid;grid-template-columns:minmax(0,1fr);gap:16px}.snapshot-view{display:block;position:relative;width:100%;padding:0;border:1px solid var(--line);border-radius:10px;overflow:hidden;background:#f2f5f5;cursor:zoom-in;text-align:left}.snapshot-view img{display:block;width:100%;height:auto;object-fit:contain}.snapshot-view span{display:block;padding:12px 16px;color:var(--ink);font-family:inherit;font-size:14px;font-weight:700;background:var(--blue-soft)}.compare.actual-only .snapshot-view:first-child{display:none}.compare.actual-only{grid-template-columns:1fr}.text-button{border:0;background:none;color:var(--blue);font-family:inherit;font-size:14px;font-weight:700;padding:16px 0 0;cursor:pointer}.text-button:hover{text-decoration:underline}.evidence-grid{display:grid;grid-template-columns:minmax(0,1fr);gap:32px}.image-button{display:block;position:relative;border:0;padding:0;width:100%;background:#edf2f2;cursor:zoom-in}.image-button img{display:block;width:100%;height:auto;object-fit:contain}.zoom{position:absolute;right:10px;bottom:10px;padding:5px 8px;border-radius:7px;background:#17212bd9;color:white;font-size:13px;opacity:1;transition:opacity .15s}.image-button:hover .zoom,.image-button:focus-visible .zoom{opacity:1}.evidence-copy{padding:24px 24px 0}.proof{display:grid;grid-template-columns:1.2fr .8fr;gap:16px}.panel{border:1px solid var(--line);border-radius:16px;padding:20px;background:#fff;box-shadow:var(--shadow)}.panel p{color:var(--muted);margin:7px 0 0;font-size:13px}.checks{display:grid;gap:10px;margin-top:13px}.check{display:flex;gap:10px;align-items:start;font-size:13px}.check i{width:19px;height:19px;flex:0 0 19px;border-radius:50%;background:var(--green-soft);color:var(--green);font-style:normal;text-align:center;font-size:13px;font-weight:900}.pending i{background:var(--amber-soft);color:var(--amber)}.meta{display:grid;gap:13px;margin-top:14px}.meta div{padding-bottom:12px;border-bottom:1px solid var(--line)}.meta div:last-child{border-bottom:0;padding-bottom:0}.meta small{display:block;color:var(--muted);font-size:11px}.meta strong{display:block;font-size:13px;margin-top:3px;overflow-wrap:anywhere}.footer{margin-top:44px;padding-top:18px;border-top:1px solid var(--line);color:var(--muted);font-size:12px}.modal{position:fixed;inset:0;display:none;overflow:auto;padding:64px 24px 24px;background:#12212acc;z-index:5}.modal.open{display:block}.modal-inner{width:max-content;margin:0 auto;position:relative}.modal img{display:block;width:auto;height:auto;max-width:none;max-height:none;border-radius:10px;box-shadow:0 20px 60px #0008}.close{position:fixed;right:24px;top:16px;border:0;background:#fff;color:var(--ink);border-radius:8px;padding:9px 14px;font-family:inherit;font-size:14px;font-weight:700;cursor:pointer}.snapshot-view:focus-visible,.image-button:focus-visible,.text-button:focus-visible,.close:focus-visible{outline:3px solid #78aeba;outline-offset:3px}.change-notes{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:24px;margin:20px 0 24px}.change-notes div{min-width:0}.change-notes dt{color:var(--blue);font-size:13px;font-weight:750;margin-bottom:6px}.change-notes dd{margin:0;font-size:15px;line-height:1.6;color:var(--ink);overflow-wrap:anywhere}.gallery-nav{display:flex;flex-wrap:wrap;gap:8px 20px;padding:16px 0;border-block:1px solid var(--line)}.gallery-nav a{color:var(--blue);font-size:14px;text-underline-offset:4px}.pair-card,.evidence-card{scroll-margin-top:20px}@media(max-width:800px){main{padding:30px 16px 60px}.hero{display:block}.stamp{margin-top:20px}.stats{grid-template-columns:repeat(2,1fr);margin-bottom:36px}.grid,.proof{grid-template-columns:1fr}.evidence-grid{grid-template-columns:minmax(0,1fr)}.change-notes{grid-template-columns:minmax(0,1fr)}.pair-card{padding:16px}.evidence-copy{padding:16px 16px 0}.section-intro{display:block}.section-intro p{margin-top:8px}}@media(max-width:480px){h1{font-size:40px}.evidence-grid{grid-template-columns:1fr}.section-intro{display:block}.section-intro p{margin-top:8px}}
</style></head><body><main>
<header class="hero"><div><p class="kicker">10x / integration evidence</p><h1>What moved forward in this session</h1><p class="dek">Large screenshots with a guide to what changed, why it matters, and where to look. Evidence captured on September 8, 2026.</p></div><div class="stamp">Evidence captured<strong>08 Sep 2026</strong><span>Local integration branch</span></div></header>
<section class="stats" aria-label="Progress totals"><div class="stat"><strong>14</strong><span>audit items implemented or verified</span></div><div class="stat"><strong>13/14</strong><span>native acceptance items passing</span></div><div class="stat"><strong>1,591</strong><span>combined app tests executed</span></div><div class="stat"><strong>16/16</strong><span>changed snapshot refs reviewed</span></div></section>
<nav class="gallery-nav" aria-label="Jump to an improvement">${jumpLinks}</nav>
<section class="section"><div class="section-intro"><div><p class="kicker">Visible product changes</p><h2>Before and after, rendered snapshots</h2></div><p>Each pair shows the older reference followed by the combined build. Open an image to inspect it at its original size; tall images can be scrolled.</p></div><div class="grid">${pairMarkup}</div></section>
<section class="section"><div class="section-intro"><div><p class="kicker">Native proof</p><h2>Local Release build evidence</h2></div><p>These captures come from the local Release build and show the flows that matter in use: persistence, recovery, queuing, warnings, and controls.</p></div><div class="evidence-grid">${nativeMarkup}</div></section>
<section class="section proof"><div class="panel"><p class="kicker">Verified in the combined run</p><h2>Working slice</h2><div class="checks"><div class="check"><i>✓</i><span>Changed-file links, path insertion at caret, and native Undo/Redo.</span></div><div class="check"><i>✓</i><span>A/B unsent drafts, image attachment, quit/relaunch recovery, and route restore.</span></div><div class="check"><i>✓</i><span>Pending input stays readable, header/composer jumps work, and Command-Period cancels safely.</span></div><div class="check"><i>✓</i><span>Queued follow-up badge and exactly-once persistence through delivery.</span></div><div class="check"><i>✓</i><span>Controlled compaction failure, progress, Stop, independent warnings, and Global OMP scope.</span></div></div></div><div class="panel"><p class="kicker">Proof panel</p><h2>Branch and test record</h2><div class="meta"><div><small>Combined app tests</small><strong>1,591 executed, zero behavioral failures</strong></div><div><small>Snapshot review</small><strong>16 intentional refs visually reviewed, focused rerun passed</strong></div><div><small>Integration branch</small><strong>codex/active-session-audit-integration</strong></div><div><small>Release package</small><strong>10x-integration.app</strong></div><div><small>Source</small><strong>fa22abbb1263</strong></div><div><small>Supporting suite</small><strong>OmpKit: 222 passing, 3 opt-in live tests skipped</strong></div></div></div></section>
<section class="section"><div class="panel"><p class="kicker">Open edges</p><h2>Still to close</h2><div class="checks"><div class="check pending"><i>!</i><span>Live CJK candidate composition remains pending Apple Pinyin approval.</span></div><div class="check pending"><i>!</i><span>Four activity snapshots still exactly match the pre-merge main failures.</span></div><div class="check pending"><i>!</i><span>Long provider shell work exposed raw background job notices and one premature model completion response. Follow-up concern.</span></div><div class="check pending"><i>!</i><span>No GitHub merge or deployment has happened.</span></div></div></div></section>
<footer class="footer">Source: local audit evidence collected on the integration branch. The queue screenshot intentionally retains visible raw background job notices.</footer></main><div class="modal" role="dialog" aria-modal="true" aria-label="Full screenshot"><div class="modal-inner"><button class="close" type="button">Close</button><img alt=""></div></div>
<script>document.querySelectorAll('.compare-toggle').forEach((button)=>button.addEventListener('click',()=>{const compare=button.previousElementSibling;const active=compare.classList.toggle('actual-only');button.textContent=active?'Show before and after':'Show after only'}));const modal=document.querySelector('.modal'),modalImg=modal.querySelector('img'),closeButton=modal.querySelector('.close');let opener=null;const close=()=>{modal.classList.remove('open');modalImg.src='';if(opener)opener.focus();};document.querySelectorAll('.image-button,.snapshot-view').forEach((button)=>button.addEventListener('click',()=>{opener=button;modalImg.src=button.dataset.full;modalImg.alt=button.dataset.alt;modal.classList.add('open');closeButton.focus();}));modal.addEventListener('click',(event)=>{if(event.target===modal)close()});closeButton.addEventListener('click',close);document.addEventListener('keydown',(event)=>{if(!modal.classList.contains('open'))return;if(event.key==='Escape'){close();return}if(event.key==='Tab'){event.preventDefault();closeButton.focus()}});</script></body></html>`;
fs.writeFileSync(path.join(root, 'progress-gallery.html'), html);
console.log(`Wrote ${path.join(root, 'progress-gallery.html')} (${Buffer.byteLength(html)} bytes)`);

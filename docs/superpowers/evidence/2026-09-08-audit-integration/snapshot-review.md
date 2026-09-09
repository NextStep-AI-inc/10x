# Integrated snapshot review

Source: `fa22abbb1263bcc3cfd78edbfefb21053c7f664f`. The parent inspected all sixteen candidate actuals in light/dark and compact/wide variants, with representative old/new pairs, before updating these references. This changes test images only; it does not alter the packaged app.

| Images | Accepted difference |
| --- | --- |
| active-session-header (light/dark), composer-stop-control (light/dark), composer-sends-attachment-mid-run, composer-command-browser-streaming-steer | New shared Working status. Header metadata truncates inside the available width; composer controls remain legible and separated. |
| chat-full-1440, chat-full-900, chat-full-900-slim | Shared activity status in both header and composer; existing transcript detail and controls remain readable at the respective widths. |
| developer-tool-flow (light/dark) | Diff file heading is now the clickable preferred-editor reference; active output shows its latest ten lines (5–14), with older output still available. |
| rich-transcript-wide (light/dark), rich-transcript-compact | Redundant Working spinner removed while active tool cards already convey work. Prose, code wrapping, and tool groups remain intact. |
| continuous-settings (light/dark) | Current-main OMP/10x settings navigation retained, together with this feature’s Global OMP defaults label. The old images predate the main settings redesign; the layout change is not attributed wholly to this integration. |

Four failed activity actuals match the pre-merge current-main output byte for byte: `activity-structured-diff`, `activity-structured-diff-dark`, `activity-running-error`, and `activity-running-error-dark`. Their references are deliberately not updated, and the suite is not reported as fully green. See `main-baseline.json` and `combined-first-run.json` for the hashes.

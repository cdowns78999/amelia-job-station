# Amelia Job Search

One repository, two parts.

- `widget/` The Amelia Job Search widget people install. Slider 1 Job Search, slider 2 Job Station (Indeed and LinkedIn; each with On Deck, Off Focus, Park, plus Collect All). On every launch the installed widget reads `version.json` and the newest GitHub release here and updates itself when a newer one exists.
- `relay/` The listener that runs on the search computer only. It picks up searches from https://amelia-job-hunt.netlify.app/api/relay, runs one unattended search, and sends back the 9-field cluster txt.

No secrets live here. The relay key stays in `%LOCALAPPDATA%\AmeliaRelay\relay-key.txt` on the search computer, and each widget makes its own key at install.

Source of truth for edits: `00302-Widget-Master\amelia-job-station` (widget) and `00102-build\amelia-job-hunt\relay` (relay). Copy into this repository, bump `version.json`, then release.

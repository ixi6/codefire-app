# Electron Port — Phase 2 Tab Views Design

**Date:** 2026-03-04
**Scope:** Images, Recordings, Browser tabs

## Status

- **Built (Phase 1):** Dashboard, Sessions, Tasks (Kanban), Notes, Files, Memory, Rules, Services, Git
- **This phase:** Images, Recordings, Browser
- **Skipped:** Visualize (hidden in Swift app)

## Tab Designs

### Images

Horizontal split (w-64 / flex-1).

**Left panel:** "Image History" header. List of generated images, sorted by date descending. Each row: 40×40 thumbnail, prompt text (2-line clamp), model name, date. Delete on hover. Empty state: Image icon, "No images yet", "Generate images with AI tools".

**Right panel:** Toolbar — aspect ratio badge (mono), model badge, copy-path button, open-external button, fullscreen button. Full-size image display (centered, contain). Below: prompt text, response text if present.

**Fullscreen overlay:** Click fullscreen → dark overlay with large image, click/Escape to dismiss.

**Data source:** Existing `generatedImages` DB table. No built-in generation — images are created by external AI tools and tracked here.

**IPC channels:** `images:list`, `images:get`, `images:create`, `images:delete`.

### Recordings

Vertical layout: RecordingBar (top) + horizontal split (w-64 list / flex-1 detail).

**RecordingBar:** Title input, record/stop button, duration timer with red pulse indicator.

**Left panel:** Recording list with status icons (red pulse = recording, orange spin = transcribing, green check = done, red alert = error). Each row: status icon, title, duration, date. Delete on hover. Empty state: Mic icon, "No recordings".

**Right panel:** Play/pause button (codefire-orange), title, duration + date. "Transcribe" button (purple) when no transcript. Transcript display as readable text. Error display with red styling.

**Recording pipeline:** Web Audio API → MediaRecorder (webm/opus) → save to app userData → OpenAI Whisper API transcription.

**API key handling:** Prompted on first transcription, stored in localStorage.

**IPC channels:** `recordings:list`, `recordings:get`, `recordings:create`, `recordings:update`, `recordings:delete`, `recordings:saveAudio`, `recordings:transcribe`.

### Browser

Full tab with: tab strip + URL toolbar + webview + optional console panel.

**Tab strip:** Horizontal tabs with title, loading spinner, close button, "+" to add. At least one tab always present.

**URL toolbar:** Back, forward, reload, home buttons. URL input with Enter to navigate. Screenshot button.

**Webview:** Electron `<webview>` tag. All tabs kept mounted (display: none for inactive). Captures console messages.

**Console panel:** Toggle from footer. Shows timestamped console entries with color coding (red errors, yellow warnings). Clear button.

**Design decision:** Start with console panel only for Phase 2. Full DevTools (Network, Elements, Styles, Storage) planned for Phase 3 if needed.

## Shared Patterns

All tabs follow established conventions:
- `text-xs`, `text-sm` sizing, `text-neutral-400` secondary text
- `border-neutral-800` separators
- `bg-neutral-900` backgrounds, `bg-neutral-800/60` hover states
- `codefire-orange` accent color
- Lucide React icons, 14-16px
- `w-64` sidebar width for list panels

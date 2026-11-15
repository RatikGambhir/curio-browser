# Favicon recovery

| | |
| --- | --- |
| **iOS status** | Not started |
| **Built on desktop** | 2026-11-13 |

## Functionality

Tab icons try the favicon declared by the page first. When the request fails,
times out, or returns an unreadable image, Curio tries the page origin's
`/favicon.ico`. The letter tile remains visible while either request is
pending and when neither icon loads.

Recent and History results in the command bar use the saved page URL to try
`/favicon.ico` directly.

## Requirements

- Build the fallback from the HTTP or HTTPS page URL's scheme, host and port.
- Try each distinct URL once per cached load. Allow five seconds per request on desktop.
- Keep storing the declared favicon URL in the existing field. No migration,
  settings, commands or additional permissions are required.

## Desktop implementation

The loader and URL selection tests live in
`browser/crates/curio-ui/src/components/favicon.rs`.

## iOS notes

`Browser/BrowserTab.swift` already supplies `/favicon.ico` for pages without
a declared icon. Pass the page origin to `UI/Components/FaviconView.swift`
so the view can also try that URL when a declared icon fails. Apply the
result only if the view still represents the requested page.
Pass the saved page URL from `UI/CommandBar/CommandResults.swift` for Recent
and History rows.

## Acceptance criteria

- [ ] A working declared favicon takes priority.
- [ ] A broken declared favicon falls back to a working same-origin `/favicon.ico`.
- [ ] If both fail, the letter tile remains.
- [ ] A Recent or History result shows the site's icon if `/favicon.ico` loads.

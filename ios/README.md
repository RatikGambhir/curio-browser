# Curio for iPhone and iPad

The Curio browser rebuilt natively in Swift and UIKit, with the same features and look as the desktop app in [`../browser`](../browser). It runs on every iPhone and iPad with iOS 17 or later, including foldable phones.

## Build and run

Requirements: Xcode 26 or later. [XcodeGen](https://github.com/yonaskolb/XcodeGen) is only needed if you change `project.yml`.

```bash
open ios/Curio.xcodeproj
```

Choose the **Curio** scheme and an iPhone or iPad simulator (or your device), then Run. To run the unit tests:

```bash
xcodebuild test -project ios/Curio.xcodeproj -scheme Curio -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

`project.yml` is the source of truth for the Xcode project. After adding or moving files, regenerate it:

```bash
cd ios && xcodegen generate
```

## One app, every screen size

The layout follows the space the window has, not the device model, so it adapts when a foldable opens or closes, when an iPad rotates, and in Split View, Slide Over and Stage Manager.

| Width | Layout |
| --- | --- |
| Narrow (iPhone, a folded foldable, iPad Slide Over) | The page card fills the screen with the address bar at the bottom, in reach of your thumb. Tabs and spaces live in a drawer (tap the sidebar button or swipe right on the bottom bar). The assistant and library open as sheets. |
| Wide (iPad, an unfolded foldable, large iPhones in landscape) | Matches the desktop: the sidebar column, the page floating as a card, and the assistant beside it. The sidebar and assistant columns can be resized by dragging their edges, and the hidden sidebar peeks when the pointer reaches the left edge. When the screen is too narrow for the sidebar, the assistant and a readable page together (an unfolded foldable, iPad mini), the sidebar steps aside while the assistant is open and can still be peeked. |

## Features

Everything from the desktop app, adapted for touch:

- **Browsing** with WebKit (the same engine as the desktop app): back/forward swipes, reload, stop, zoom, print, find in page, downloads (saved to Files › Curio › Downloads), and Safari Web Inspector.
- **Command bar** for addresses, search, open tabs, history, bookmarks, commands and questions for the assistant. All six search engines plus custom URLs.
- **Spaces** with their own name, icon, theme, tabs, pinned tabs and folders. Each space picks one of 20 gradient themes (10 light, 10 dark), and the theme decides whether that space's chrome is light or dark; web pages follow the Theme setting. The chrome cross-fades between themes when you switch spaces. Switch spaces with the footer dots or a horizontal swipe (or a two-finger trackpad swipe).
- **Tabs**: vertical sidebar or horizontal strip, pinned tabs, global favorites, folders (rename, recolor, collapse, ungroup, move to another space), drag and drop to reorder, pin, group, favorite or move tabs, swipe a tab to close or pin it, reopen closed tabs, and tab sleeping to save memory.
- **Assistant**: streaming Markdown answers with copyable code blocks, chats about the current tab, chosen tabs or the whole space, selection actions (Explain, Summarize, Translate, Ask), quick actions, and saved chat history. Works with Anthropic, OpenAI and OpenAI-compatible servers. API keys are stored in the Keychain.
- **Library** with Media, Downloads, Spaces and Archived Tabs (newest first, each with its space's dot, and searchable by space name) (plus Notes, Calendar, Clipboard History, Aliases and Inbox placeholders, as on desktop).
- **Settings** for search, session restore, memory, theme, tab layout, AI providers (with a connection test), privacy and keyboard shortcuts.
- **Keyboard and menu bar**: every desktop shortcut works with a hardware keyboard, the iPad menu bar shows Curio's menus, and shortcuts can be rebound in Settings.
- Light and dark themes, Dynamic Type sizes, VoiceOver labels, and Reduce Motion.

## Code layout

```
ios/
├── project.yml            XcodeGen spec (targets, Info.plist, build settings)
├── Curio/
│   ├── App/               App and scene delegates, Info.plist
│   ├── Core/              Tabs, tab strip, spaces/workspace, settings, chat, omnibox
│   ├── Storage/           JSON files for session, history, bookmarks, chats, downloads; Keychain
│   ├── AI/                Provider wire formats, SSE streaming, page-context prompt
│   ├── Browser/           WKWebView tab wrapper, page bridge and extraction scripts
│   ├── Session/           BrowserSession: the model and coordinator behind the UI
│   ├── UI/                Theme, components, window layout, sidebar, page, command bar,
│   │                      assistant, library, settings, dialogs, commands and menus
│   └── Resources/         Asset catalog (app icon, logo)
└── CurioTests/            Unit tests for the core, AI and settings logic
```

`Core` and `AI` are direct ports of the Rust crates (`curio-core`, `curio-tabs`, `curio-spaces`, `curio-settings`, `curio-ai`), with the same behavior and the same tests. Settings and keybinding names match the desktop app.

Debug builds accept two environment variables for quick checks: `CURIO_DEBUG_URL` opens a page on launch, and `CURIO_DEBUG_COMMANDS` runs steps such as `ToggleAiPanel,Fold,Unfold`. `Fold` and `Unfold` switch the width class the way folding a foldable phone does, so the layout change can be checked without one. `CURIO_DEBUG_STEP` sets the seconds between steps.

## Differences from the desktop app

- iOS can't choose an arbitrary download folder, so downloads always go to Curio's folder in the Files app.
- Becoming the default browser on iOS needs Apple's browser entitlement. The app already opens web links handed to it, so it's ready once the entitlement is granted.
- Developer Tools opens Safari's Web Inspector from a connected Mac instead of an in-app inspector.

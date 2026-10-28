//! Browser commands, their default shortcuts, and the macOS menu bar.
//!
//! Shortcuts use GPUI's `secondary` modifier (⌘ on macOS). Users can rebind
//! any command from settings (`keybindings`: action name to keystroke).
//! Shortcuts pressed while a web page has focus reach Curio two ways: menu
//! key equivalents (macOS routes them to the menu bar before the page), and
//! the page bridge, which forwards the keystrokes listed by
//! [`forwarded_keystrokes`].

use std::collections::BTreeMap;

use gpui_kit::{Action, App, KeyBinding, Menu, MenuItem, OsAction, SystemMenuType, actions};

actions!(
    curio,
    [
        // App
        About,
        Quit,
        OpenSettings,
        Hide,
        HideOthers,
        ShowAll,
        Minimize,
        Zoom,
        ToggleFullScreen,
        // Tabs
        NewTab,
        OpenCommandBar,
        EditUrl,
        CloseTab,
        ReopenClosedTab,
        DuplicateTab,
        PinTab,
        NextTab,
        PreviousTab,
        SelectTab1,
        SelectTab2,
        SelectTab3,
        SelectTab4,
        SelectTab5,
        SelectTab6,
        SelectTab7,
        SelectTab8,
        SelectLastTab,
        NewGroupFromTab,
        AddFavorite,
        ToggleBookmark,
        CopyUrl,
        // Navigation
        GoBack,
        GoForward,
        Reload,
        StopLoading,
        Escape,
        FindInPage,
        FindNext,
        FindPrevious,
        ZoomIn,
        ZoomOut,
        ZoomReset,
        OpenDevTools,
        Print,
        ShowHistory,
        ShowDownloads,
        // Spaces
        NewSpace,
        NextSpace,
        PreviousSpace,
        SelectSpace1,
        SelectSpace2,
        SelectSpace3,
        SelectSpace4,
        SelectSpace5,
        SelectSpace6,
        SelectSpace7,
        SelectSpace8,
        SelectSpace9,
        // Layout
        ToggleSidebar,
        ToggleTabLayout,
        ToggleAiPanel,
        // AI
        NewChat,
        AskAboutPage,
        ExplainSelection,
        SummarizeSelection,
    ]
);

/// Default shortcuts: (keystroke, action).
fn defaults() -> Vec<(&'static str, Box<dyn Action>)> {
    vec![
        ("secondary-,", Box::new(OpenSettings)),
        ("secondary-q", Box::new(Quit)),
        ("secondary-h", Box::new(Hide)),
        ("alt-secondary-h", Box::new(HideOthers)),
        ("secondary-m", Box::new(Minimize)),
        ("ctrl-secondary-f", Box::new(ToggleFullScreen)),
        ("secondary-t", Box::new(NewTab)),
        ("secondary-k", Box::new(OpenCommandBar)),
        ("secondary-l", Box::new(EditUrl)),
        ("secondary-w", Box::new(CloseTab)),
        ("shift-secondary-t", Box::new(ReopenClosedTab)),
        ("shift-secondary-k", Box::new(DuplicateTab)),
        ("secondary-d", Box::new(PinTab)),
        ("ctrl-tab", Box::new(NextTab)),
        ("ctrl-shift-tab", Box::new(PreviousTab)),
        ("shift-secondary-]", Box::new(NextTab)),
        ("shift-secondary-[", Box::new(PreviousTab)),
        ("secondary-1", Box::new(SelectTab1)),
        ("secondary-2", Box::new(SelectTab2)),
        ("secondary-3", Box::new(SelectTab3)),
        ("secondary-4", Box::new(SelectTab4)),
        ("secondary-5", Box::new(SelectTab5)),
        ("secondary-6", Box::new(SelectTab6)),
        ("secondary-7", Box::new(SelectTab7)),
        ("secondary-8", Box::new(SelectTab8)),
        ("secondary-9", Box::new(SelectLastTab)),
        ("alt-secondary-g", Box::new(NewGroupFromTab)),
        ("shift-secondary-d", Box::new(ToggleBookmark)),
        ("shift-secondary-c", Box::new(CopyUrl)),
        ("secondary-[", Box::new(GoBack)),
        ("secondary-]", Box::new(GoForward)),
        ("secondary-r", Box::new(Reload)),
        ("secondary-.", Box::new(StopLoading)),
        ("escape", Box::new(Escape)),
        ("secondary-f", Box::new(FindInPage)),
        ("secondary-g", Box::new(FindNext)),
        ("shift-secondary-g", Box::new(FindPrevious)),
        ("secondary-=", Box::new(ZoomIn)),
        ("secondary-+", Box::new(ZoomIn)),
        ("secondary--", Box::new(ZoomOut)),
        ("secondary-0", Box::new(ZoomReset)),
        ("alt-secondary-i", Box::new(OpenDevTools)),
        ("secondary-p", Box::new(Print)),
        ("secondary-y", Box::new(ShowHistory)),
        ("alt-secondary-l", Box::new(ShowDownloads)),
        ("shift-secondary-n", Box::new(NewSpace)),
        ("ctrl-secondary-right", Box::new(NextSpace)),
        ("ctrl-secondary-left", Box::new(PreviousSpace)),
        ("ctrl-1", Box::new(SelectSpace1)),
        ("ctrl-2", Box::new(SelectSpace2)),
        ("ctrl-3", Box::new(SelectSpace3)),
        ("ctrl-4", Box::new(SelectSpace4)),
        ("ctrl-5", Box::new(SelectSpace5)),
        ("ctrl-6", Box::new(SelectSpace6)),
        ("ctrl-7", Box::new(SelectSpace7)),
        ("ctrl-8", Box::new(SelectSpace8)),
        ("ctrl-9", Box::new(SelectSpace9)),
        ("secondary-s", Box::new(ToggleSidebar)),
        ("alt-secondary-t", Box::new(ToggleTabLayout)),
        ("secondary-e", Box::new(ToggleAiPanel)),
        ("shift-secondary-e", Box::new(ExplainSelection)),
        ("shift-secondary-o", Box::new(NewChat)),
    ]
}

/// The effective bindings after applying user overrides (action name to
/// keystroke; an empty keystroke unbinds the action).
#[must_use]
pub fn effective_bindings(overrides: &BTreeMap<String, String>) -> Vec<(String, Box<dyn Action>)> {
    let mut out: Vec<(String, Box<dyn Action>)> = Vec::new();
    let mut overridden = std::collections::HashSet::new();
    for (key, action) in defaults() {
        let name = action.name();
        match overrides.get(name) {
            Some(custom) => {
                if overridden.insert(name.to_owned()) && !custom.trim().is_empty() {
                    out.push((custom.trim().to_owned(), action));
                }
            }
            None => out.push((key.to_owned(), action)),
        }
    }
    out
}

/// Registers key bindings with GPUI. Invalid user keystrokes are skipped
/// with a warning instead of failing startup. Called once at launch; changed
/// shortcuts apply after a restart.
pub fn bind_keys(overrides: &BTreeMap<String, String>, cx: &mut App) {
    let mut bindings = Vec::new();
    for (key, action) in effective_bindings(overrides) {
        match KeyBinding::load(&key, action, None, false, None, cx) {
            Ok(binding) => bindings.push(binding),
            Err(error) => tracing::warn!(keystroke = %key, %error, "ignoring invalid shortcut"),
        }
    }
    cx.bind_keys(bindings);
}

/// The keystrokes (in the page bridge's `ctrl-alt-shift-cmd-key` format)
/// that pages should forward to Curio. Escape is excluded so pages keep it.
#[must_use]
pub fn forwarded_keystrokes(overrides: &BTreeMap<String, String>) -> Vec<String> {
    effective_bindings(overrides)
        .into_iter()
        .filter_map(|(key, _)| bridge_keystroke(&key))
        .collect()
}

/// Converts a GPUI keystroke like `shift-secondary-t` into the bridge's
/// canonical order. Returns `None` for keys without a modifier.
#[must_use]
pub fn bridge_keystroke(key: &str) -> Option<String> {
    let parts: Vec<&str> = key.split('-').collect();
    // A trailing "-" means the key itself is minus ("secondary--").
    let (mods, key_name) = if key.ends_with("--") {
        (&parts[..parts.len().saturating_sub(2)], "-")
    } else {
        let (last, rest) = parts.split_last()?;
        (rest, *last)
    };
    let secondary = if cfg!(target_os = "macos") { "cmd" } else { "ctrl" };
    let mut ctrl = false;
    let mut alt = false;
    let mut shift = false;
    let mut cmd = false;
    for m in mods {
        match *m {
            "ctrl" => ctrl = true,
            "alt" => alt = true,
            "shift" => shift = true,
            "cmd" => cmd = true,
            "secondary" => {
                if secondary == "cmd" {
                    cmd = true;
                } else {
                    ctrl = true;
                }
            }
            _ => return None,
        }
    }
    if !(ctrl || alt || cmd) {
        return None;
    }
    let mut out = String::new();
    if ctrl {
        out.push_str("ctrl-");
    }
    if alt {
        out.push_str("alt-");
    }
    if shift {
        out.push_str("shift-");
    }
    if cmd {
        out.push_str("cmd-");
    }
    out.push_str(key_name);
    Some(out)
}

/// Finds the action bound to a bridge keystroke.
#[must_use]
pub fn action_for_bridge_keystroke(
    keystroke: &str,
    overrides: &BTreeMap<String, String>,
) -> Option<Box<dyn Action>> {
    effective_bindings(overrides)
        .into_iter()
        .find(|(key, _)| bridge_keystroke(key).as_deref() == Some(keystroke))
        .map(|(_, action)| action)
}

/// The macOS menu bar.
#[must_use]
pub fn menus() -> Vec<Menu> {
    vec![
        Menu::new("Curio").items([
            MenuItem::action("About Curio", About),
            MenuItem::separator(),
            MenuItem::action("Settings…", OpenSettings),
            MenuItem::separator(),
            MenuItem::os_submenu("Services", SystemMenuType::Services),
            MenuItem::separator(),
            MenuItem::action("Hide Curio", Hide),
            MenuItem::action("Hide Others", HideOthers),
            MenuItem::action("Show All", ShowAll),
            MenuItem::separator(),
            MenuItem::action("Quit Curio", Quit),
        ]),
        Menu::new("File").items([
            MenuItem::action("New Tab", NewTab),
            MenuItem::action("New Space", NewSpace),
            MenuItem::action("New Chat", NewChat),
            MenuItem::separator(),
            MenuItem::action("Open Location…", EditUrl),
            MenuItem::action("Command Bar…", OpenCommandBar),
            MenuItem::separator(),
            MenuItem::action("Close Tab", CloseTab),
            MenuItem::action("Reopen Closed Tab", ReopenClosedTab),
            MenuItem::separator(),
            MenuItem::action("Print…", Print),
        ]),
        Menu::new("Edit").items([
            MenuItem::os_action("Undo", gpui_kit::component::input::Undo, OsAction::Undo),
            MenuItem::os_action("Redo", gpui_kit::component::input::Redo, OsAction::Redo),
            MenuItem::separator(),
            MenuItem::os_action("Cut", gpui_kit::component::input::Cut, OsAction::Cut),
            MenuItem::os_action("Copy", gpui_kit::component::input::Copy, OsAction::Copy),
            MenuItem::os_action("Paste", gpui_kit::component::input::Paste, OsAction::Paste),
            MenuItem::os_action(
                "Select All",
                gpui_kit::component::input::SelectAll,
                OsAction::SelectAll,
            ),
            MenuItem::separator(),
            MenuItem::action("Find…", FindInPage),
            MenuItem::action("Find Next", FindNext),
            MenuItem::action("Find Previous", FindPrevious),
            MenuItem::separator(),
            MenuItem::action("Copy URL", CopyUrl),
        ]),
        Menu::new("View").items([
            MenuItem::action("Toggle Sidebar", ToggleSidebar),
            MenuItem::action("Toggle AI Assistant", ToggleAiPanel),
            MenuItem::action("Switch Tab Layout", ToggleTabLayout),
            MenuItem::separator(),
            MenuItem::action("Reload Page", Reload),
            MenuItem::action("Stop Loading", StopLoading),
            MenuItem::separator(),
            MenuItem::action("Zoom In", ZoomIn),
            MenuItem::action("Zoom Out", ZoomOut),
            MenuItem::action("Actual Size", ZoomReset),
            MenuItem::separator(),
            MenuItem::action("Enter Full Screen", ToggleFullScreen),
            MenuItem::separator(),
            MenuItem::action("Developer Tools", OpenDevTools),
        ]),
        Menu::new("History").items([
            MenuItem::action("Back", GoBack),
            MenuItem::action("Forward", GoForward),
            MenuItem::separator(),
            MenuItem::action("Show History", ShowHistory),
            MenuItem::action("Downloads", ShowDownloads),
        ]),
        Menu::new("Tab").items([
            MenuItem::action("Pin / Unpin Tab", PinTab),
            MenuItem::action("Duplicate Tab", DuplicateTab),
            MenuItem::action("Add to Favorites", AddFavorite),
            MenuItem::action("Bookmark Page", ToggleBookmark),
            MenuItem::action("New Group from Tab", NewGroupFromTab),
            MenuItem::separator(),
            MenuItem::action("Next Tab", NextTab),
            MenuItem::action("Previous Tab", PreviousTab),
        ]),
        Menu::new("Spaces").items([
            MenuItem::action("New Space", NewSpace),
            MenuItem::separator(),
            MenuItem::action("Next Space", NextSpace),
            MenuItem::action("Previous Space", PreviousSpace),
        ]),
        Menu::new("Assistant").items([
            MenuItem::action("Toggle Assistant", ToggleAiPanel),
            MenuItem::action("New Chat", NewChat),
            MenuItem::separator(),
            MenuItem::action("Summarize Page", AskAboutPage),
            MenuItem::action("Explain Selection", ExplainSelection),
            MenuItem::action("Summarize Selection", SummarizeSelection),
        ]),
        Menu::new("Window").items([
            MenuItem::action("Minimize", Minimize),
            MenuItem::action("Zoom", Zoom),
        ]),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bridge_keystrokes_use_canonical_order() {
        let cmd = if cfg!(target_os = "macos") { "cmd-" } else { "" };
        let ctrl = if cfg!(target_os = "macos") { "" } else { "ctrl-" };
        assert_eq!(
            bridge_keystroke("shift-secondary-t").as_deref(),
            Some(format!("{ctrl}shift-{cmd}t").as_str())
        );
        assert_eq!(
            bridge_keystroke("secondary--").as_deref(),
            Some(format!("{ctrl}{cmd}-").as_str())
        );
        assert_eq!(bridge_keystroke("escape"), None);
        assert_eq!(bridge_keystroke("ctrl-tab").as_deref(), Some("ctrl-tab"));
    }

    #[test]
    fn overrides_replace_and_unbind() {
        let mut overrides = BTreeMap::new();
        overrides.insert("curio::NewTab".to_owned(), "secondary-n".to_owned());
        overrides.insert("curio::Print".to_owned(), String::new());
        let bindings = effective_bindings(&overrides);
        assert!(bindings.iter().any(|(k, a)| k == "secondary-n" && a.name() == "curio::NewTab"));
        assert!(!bindings.iter().any(|(_, a)| a.name() == "curio::Print"));
    }

    #[test]
    fn duplicate_default_bindings_collapse_on_override() {
        let mut overrides = BTreeMap::new();
        overrides.insert("curio::NextTab".to_owned(), "alt-tab".to_owned());
        let next: Vec<_> = effective_bindings(&overrides)
            .into_iter()
            .filter(|(_, a)| a.name() == "curio::NextTab")
            .collect();
        assert_eq!(next.len(), 1);
    }
}

//! Spaces and the workspace that owns them.
//!
//! A [`Workspace`] is the complete, persistable organization of the browser:
//! an ordered list of [`Space`]s (each with its own tabs, pinned tabs, groups,
//! name, icon, color and active tab), global favorites, and the stack of
//! recently closed tabs. It contains no engine or UI state, so every
//! operation here is synchronous and unit tested.

use std::collections::VecDeque;

use curio_core::time::now_ms;
use curio_core::{AccentColor, Favorite, FavoriteId, GroupId, SpaceId, Tab, TabId};
use curio_tabs::{Placement, Section, TabStrip};
use serde::{Deserialize, Serialize};

/// How many closed tabs "Reopen Closed Tab" remembers.
pub const CLOSED_TAB_LIMIT: usize = 50;

/// Icons offered when creating or customizing a space.
pub const SPACE_ICONS: [&str; 24] = [
    "✦", "☀︎", "☾", "◆", "●", "▲", "♠︎", "♣︎", "♥︎", "⚑", "✿", "❖", "🧭", "🔭", "🧪", "📚", "💼",
    "🎨", "🎧", "🌿", "🏔", "⚡️", "🚀", "🏠",
];

/// An independent browsing context with its own tabs and appearance.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Space {
    pub id: SpaceId,
    pub name: String,
    /// A short glyph or emoji shown in the space switcher.
    pub icon: String,
    pub color: AccentColor,
    pub strip: TabStrip,
    /// The tab shown when this space is active. May refer to a favorite's tab.
    pub active_tab: Option<TabId>,
}

impl Default for Space {
    fn default() -> Self {
        Self {
            id: SpaceId::new(),
            name: "Space".to_owned(),
            icon: SPACE_ICONS[0].to_owned(),
            color: AccentColor::default(),
            strip: TabStrip::new(),
            active_tab: None,
        }
    }
}

impl Space {
    /// Creates an empty space.
    #[must_use]
    pub fn new(name: impl Into<String>, icon: impl Into<String>, color: AccentColor) -> Self {
        Self {
            name: name.into(),
            icon: icon.into(),
            color,
            ..Self::default()
        }
    }
}

/// Which collection owns a tab.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TabOwner {
    Space(SpaceId),
    Favorite(FavoriteId),
}

/// A closed tab remembered for "Reopen Closed Tab".
#[derive(Debug, Clone, PartialEq)]
pub struct ClosedTab {
    pub space: SpaceId,
    pub tab: Tab,
    pub restore_at: Placement,
}

/// The result of closing a tab.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Closed {
    /// The space that owned the tab.
    pub space: SpaceId,
    /// The tab that became active in that space, if any.
    pub next_active: Option<TabId>,
}

/// The full browser organization.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Workspace {
    spaces: Vec<Space>,
    favorites: Vec<Favorite>,
    active_space: SpaceId,
    #[serde(skip)]
    closed: VecDeque<ClosedTab>,
}

impl Default for Workspace {
    fn default() -> Self {
        Self::with_spaces(vec![Space::new("Personal", "✦", AccentColor::Iris)], Vec::new())
    }
}

impl Workspace {
    /// Builds a workspace from persisted parts. An empty `spaces` list gets a
    /// default space so the browser always has somewhere to put tabs.
    #[must_use]
    pub fn with_spaces(mut spaces: Vec<Space>, favorites: Vec<Favorite>) -> Self {
        if spaces.is_empty() {
            spaces.push(Space::new("Personal", "✦", AccentColor::Iris));
        }
        let active_space = spaces[0].id;
        let mut workspace = Self {
            spaces,
            favorites,
            active_space,
            closed: VecDeque::new(),
        };
        // Drop active-tab references that no longer resolve.
        for index in 0..workspace.spaces.len() {
            if let Some(active) = workspace.spaces[index].active_tab
                && workspace.find_tab(active).is_none()
            {
                workspace.spaces[index].active_tab = None;
            }
        }
        workspace
    }

    /// A first-run workspace with two starter spaces.
    #[must_use]
    pub fn first_run() -> Self {
        let personal = Space::new("Personal", "✦", AccentColor::Iris);
        let work = Space::new("Work", "💼", AccentColor::Lagoon);
        Self::with_spaces(vec![personal, work], Vec::new())
    }

    // ----- Spaces -------------------------------------------------------

    /// All spaces in sidebar order.
    #[must_use]
    pub fn spaces(&self) -> &[Space] {
        &self.spaces
    }

    /// Looks up a space.
    #[must_use]
    pub fn space(&self, id: SpaceId) -> Option<&Space> {
        self.spaces.iter().find(|s| s.id == id)
    }

    /// Looks up a space for mutation.
    pub fn space_mut(&mut self, id: SpaceId) -> Option<&mut Space> {
        self.spaces.iter_mut().find(|s| s.id == id)
    }

    /// The id of the active space.
    #[must_use]
    pub fn active_space_id(&self) -> SpaceId {
        self.active_space
    }

    /// The active space.
    #[must_use]
    pub fn active_space(&self) -> &Space {
        self.space(self.active_space)
            .unwrap_or_else(|| &self.spaces[0])
    }

    /// The active space, mutably.
    pub fn active_space_mut(&mut self) -> &mut Space {
        let id = self.active_space;
        let index = self.spaces.iter().position(|s| s.id == id).unwrap_or(0);
        &mut self.spaces[index]
    }

    /// Index of a space in the switcher.
    #[must_use]
    pub fn space_index(&self, id: SpaceId) -> Option<usize> {
        self.spaces.iter().position(|s| s.id == id)
    }

    /// Creates a space after the existing ones and returns its id.
    pub fn create_space(
        &mut self,
        name: impl Into<String>,
        icon: impl Into<String>,
        color: Option<AccentColor>,
    ) -> SpaceId {
        let color = color.unwrap_or_else(|| {
            self.spaces
                .last()
                .map_or(AccentColor::Iris, |space| space.color.next())
        });
        let space = Space::new(name, icon, color);
        let id = space.id;
        self.spaces.push(space);
        id
    }

    /// Renames a space. Blank names are ignored.
    pub fn rename_space(&mut self, id: SpaceId, name: &str) -> bool {
        let name = name.trim();
        match self.space_mut(id) {
            Some(space) if !name.is_empty() => {
                name.clone_into(&mut space.name);
                true
            }
            _ => false,
        }
    }

    /// Changes a space's icon.
    pub fn set_space_icon(&mut self, id: SpaceId, icon: &str) -> bool {
        match self.space_mut(id) {
            Some(space) if !icon.trim().is_empty() => {
                icon.trim().clone_into(&mut space.icon);
                true
            }
            _ => false,
        }
    }

    /// Changes a space's accent color.
    pub fn set_space_color(&mut self, id: SpaceId, color: AccentColor) -> bool {
        self.space_mut(id).map(|s| s.color = color).is_some()
    }

    /// Deletes a space and its tabs. The last space cannot be deleted.
    /// Returns the removed space so the caller can release engine resources.
    pub fn delete_space(&mut self, id: SpaceId) -> Option<Space> {
        if self.spaces.len() <= 1 {
            return None;
        }
        let index = self.space_index(id)?;
        let removed = self.spaces.remove(index);
        if self.active_space == id {
            let next = index.min(self.spaces.len() - 1);
            self.active_space = self.spaces[next].id;
        }
        self.closed.retain(|closed| closed.space != id);
        Some(removed)
    }

    /// Moves a space to `new_index` (clamped).
    pub fn move_space(&mut self, id: SpaceId, new_index: usize) -> bool {
        let Some(index) = self.space_index(id) else {
            return false;
        };
        let space = self.spaces.remove(index);
        let new_index = new_index.min(self.spaces.len());
        self.spaces.insert(new_index, space);
        true
    }

    /// Activates a space.
    pub fn switch_space(&mut self, id: SpaceId) -> bool {
        if self.space(id).is_some() && self.active_space != id {
            self.active_space = id;
            true
        } else {
            false
        }
    }

    /// The space next to the active one (`forward` = right), if any.
    #[must_use]
    pub fn adjacent_space(&self, forward: bool) -> Option<SpaceId> {
        let index = self.space_index(self.active_space)?;
        let target = if forward {
            index.checked_add(1)?
        } else {
            index.checked_sub(1)?
        };
        self.spaces.get(target).map(|s| s.id)
    }

    // ----- Tabs ---------------------------------------------------------

    /// Finds a tab in any space or favorite.
    #[must_use]
    pub fn find_tab(&self, id: TabId) -> Option<(TabOwner, &Tab)> {
        if let Some(fav) = self.favorites.iter().find(|f| f.tab.id == id) {
            return Some((TabOwner::Favorite(fav.id), &fav.tab));
        }
        self.spaces
            .iter()
            .find_map(|s| s.strip.tab(id).map(|t| (TabOwner::Space(s.id), t)))
    }

    /// Looks up a tab in any space or favorite.
    #[must_use]
    pub fn tab(&self, id: TabId) -> Option<&Tab> {
        self.find_tab(id).map(|(_, tab)| tab)
    }

    /// Looks up a tab for mutation.
    pub fn tab_mut(&mut self, id: TabId) -> Option<&mut Tab> {
        if let Some(fav) = self.favorites.iter_mut().find(|f| f.tab.id == id) {
            return Some(&mut fav.tab);
        }
        self.spaces.iter_mut().find_map(|s| s.strip.tab_mut(id))
    }

    /// The space that owns a tab, if it is not a favorite.
    #[must_use]
    pub fn space_of_tab(&self, id: TabId) -> Option<SpaceId> {
        self.spaces
            .iter()
            .find(|s| s.strip.contains(id))
            .map(|s| s.id)
    }

    /// The active tab of the active space.
    #[must_use]
    pub fn active_tab_id(&self) -> Option<TabId> {
        self.active_space().active_tab
    }

    /// The active tab of the active space.
    #[must_use]
    pub fn active_tab(&self) -> Option<&Tab> {
        self.active_tab_id().and_then(|id| self.tab(id))
    }

    /// Opens a tab in `space` and returns its id. When `activate` is set, the
    /// tab becomes the space's active tab.
    pub fn open_tab(
        &mut self,
        space: SpaceId,
        tab: Tab,
        placement: Placement,
        activate: bool,
    ) -> Option<TabId> {
        let space = self.space_mut(space)?;
        let id = space.strip.insert(tab, placement);
        if activate {
            space.active_tab = Some(id);
        }
        Some(id)
    }

    /// Opens a tab in the active space, next to the active tab when it is a
    /// regular tab (like Arc and Chrome), or at the top of the unpinned
    /// section otherwise.
    pub fn open_tab_in_active_space(&mut self, tab: Tab, activate: bool) -> TabId {
        let space_id = self.active_space;
        let placement = self.placement_near_active();
        let id = tab.id;
        self.open_tab(space_id, tab, placement, activate);
        id
    }

    fn placement_near_active(&self) -> Placement {
        let space = self.active_space();
        match space.active_tab.and_then(|id| space.strip.location_of(id).map(|l| (id, l))) {
            Some((id, location)) if location.section == Section::Unpinned => {
                Placement::AfterTab(id)
            }
            _ => Placement::SectionStart(Section::Unpinned),
        }
    }

    /// Activates a tab, switching to its space when needed. Favorites open
    /// in the active space. Returns `false` for unknown tabs.
    pub fn activate_tab(&mut self, id: TabId) -> bool {
        let Some((owner, _)) = self.find_tab(id) else {
            return false;
        };
        if let TabOwner::Space(space) = owner {
            self.active_space = space;
        }
        self.active_space_mut().active_tab = Some(id);
        if let Some(tab) = self.tab_mut(id) {
            tab.last_active_at = now_ms();
        }
        true
    }

    /// Closes a regular tab, remembering it for reopening. Favorites cannot
    /// be closed this way (see [`Workspace::remove_favorite`]).
    pub fn close_tab(&mut self, id: TabId) -> Option<Closed> {
        let space_id = self.space_of_tab(id)?;
        let space = self.space_mut(space_id)?;
        let next = space.strip.neighbor_for_close(id);
        let removed = space.strip.remove(id)?;
        if space.active_tab == Some(id) {
            space.active_tab = next;
        }
        let next_active = space.active_tab;
        self.closed.push_front(ClosedTab {
            space: space_id,
            tab: removed.tab,
            restore_at: removed.restore_at,
        });
        self.closed.truncate(CLOSED_TAB_LIMIT);
        // Spaces showing a favorite that is unrelated stay as they are.
        Some(Closed {
            space: space_id,
            next_active,
        })
    }

    /// Reopens the most recently closed tab in its original space and
    /// position, and activates it.
    pub fn reopen_closed_tab(&mut self) -> Option<TabId> {
        while let Some(closed) = self.closed.pop_front() {
            if self.space(closed.space).is_none() {
                continue;
            }
            let id = closed.tab.id;
            self.open_tab(closed.space, closed.tab, closed.restore_at, true)?;
            self.active_space = closed.space;
            return Some(id);
        }
        None
    }

    /// Number of tabs that can be reopened.
    #[must_use]
    pub fn closed_tab_count(&self) -> usize {
        self.closed.len()
    }

    /// Duplicates a tab next to the original and returns the copy's id.
    pub fn duplicate_tab(&mut self, id: TabId) -> Option<TabId> {
        let copy = self.tab(id)?.duplicate();
        let copy_id = copy.id;
        match self.space_of_tab(id) {
            Some(space) => {
                let placement = if self.space(space)?.strip.is_pinned(id) {
                    Placement::SectionStart(Section::Unpinned)
                } else {
                    Placement::AfterTab(id)
                };
                self.open_tab(space, copy, placement, true)?;
            }
            None => {
                let space = self.active_space;
                self.open_tab(space, copy, Placement::SectionStart(Section::Unpinned), true)?;
            }
        }
        Some(copy_id)
    }

    /// Moves a tab to another space (to the top of its unpinned section).
    pub fn move_tab_to_space(&mut self, id: TabId, target: SpaceId) -> bool {
        let Some(source) = self.space_of_tab(id) else {
            return false;
        };
        if source == target || self.space(target).is_none() {
            return false;
        }
        let Some(source_space) = self.space_mut(source) else {
            return false;
        };
        let next = source_space.strip.neighbor_for_close(id);
        let Some(removed) = source_space.strip.remove(id) else {
            return false;
        };
        if source_space.active_tab == Some(id) {
            source_space.active_tab = next;
        }
        self.open_tab(
            target,
            removed.tab,
            Placement::SectionStart(Section::Unpinned),
            false,
        )
        .is_some()
    }

    /// Moves a whole group (and its tabs) to another space.
    pub fn move_group_to_space(&mut self, group: GroupId, source: SpaceId, target: SpaceId) -> bool {
        if source == target || self.space(target).is_none() {
            return false;
        }
        let Some(source_space) = self.space_mut(source) else {
            return false;
        };
        let Some((group, tabs, section)) = source_space.strip.take_group(group) else {
            return false;
        };
        if let Some(active) = source_space.active_tab
            && tabs.iter().any(|t| t.id == active)
        {
            source_space.active_tab = source_space.strip.ordered_tab_ids().first().copied();
        }
        match self.space_mut(target) {
            Some(target) => {
                target.strip.insert_group(group, tabs, section);
                true
            }
            None => false,
        }
    }

    /// Every tab with its owner, favorites first, then spaces in order.
    pub fn all_tabs(&self) -> impl Iterator<Item = (TabOwner, &Tab)> {
        self.favorites
            .iter()
            .map(|f| (TabOwner::Favorite(f.id), &f.tab))
            .chain(self.spaces.iter().flat_map(|s| {
                s.strip
                    .ordered_tab_ids()
                    .into_iter()
                    .filter_map(move |id| s.strip.tab(id).map(|t| (TabOwner::Space(s.id), t)))
            }))
    }

    // ----- Favorites ----------------------------------------------------

    /// Global favorites in order.
    #[must_use]
    pub fn favorites(&self) -> &[Favorite] {
        &self.favorites
    }

    /// Adds a favorite for a URL; returns `None` when it already exists.
    pub fn add_favorite(&mut self, url: &str, title: &str, favicon: Option<String>) -> Option<FavoriteId> {
        if self
            .favorites
            .iter()
            .any(|f| f.tab.home_url.as_deref() == Some(url))
        {
            return None;
        }
        let mut favorite = Favorite::new(url, title);
        favorite.tab.favicon_url = favicon;
        let id = favorite.id;
        self.favorites.push(favorite);
        Some(id)
    }

    /// Converts a regular tab into a favorite, keeping its page state.
    pub fn favorite_from_tab(&mut self, id: TabId) -> Option<FavoriteId> {
        let space_id = self.space_of_tab(id)?;
        let space = self.space_mut(space_id)?;
        let next = space.strip.neighbor_for_close(id);
        let removed = space.strip.remove(id)?;
        let mut tab = removed.tab;
        tab.home_url = Some(tab.url.clone());
        let favorite = Favorite {
            id: FavoriteId::new(),
            tab,
        };
        let fav_id = favorite.id;
        // The tab keeps its identity; keep it active if it was.
        let was_active = space.active_tab == Some(id);
        if was_active {
            space.active_tab = Some(id);
        } else if space.active_tab.is_none() {
            space.active_tab = next;
        }
        self.favorites.push(favorite);
        Some(fav_id)
    }

    /// Removes a favorite and returns it. Spaces showing it fall back to
    /// their first tab.
    pub fn remove_favorite(&mut self, id: FavoriteId) -> Option<Favorite> {
        let index = self.favorites.iter().position(|f| f.id == id)?;
        let favorite = self.favorites.remove(index);
        for space in &mut self.spaces {
            if space.active_tab == Some(favorite.tab.id) {
                space.active_tab = space.strip.ordered_tab_ids().first().copied();
            }
        }
        Some(favorite)
    }

    /// Moves a favorite to `new_index` (clamped).
    pub fn move_favorite(&mut self, id: FavoriteId, new_index: usize) -> bool {
        let Some(index) = self.favorites.iter().position(|f| f.id == id) else {
            return false;
        };
        let favorite = self.favorites.remove(index);
        let new_index = new_index.min(self.favorites.len());
        self.favorites.insert(new_index, favorite);
        true
    }

    /// Restores the persisted active space, if it still exists.
    pub fn restore_active_space(&mut self, id: SpaceId) {
        if self.space(id).is_some() {
            self.active_space = id;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn workspace_with_tabs() -> (Workspace, SpaceId, SpaceId, Vec<TabId>) {
        let mut ws = Workspace::first_run();
        let a = ws.spaces()[0].id;
        let b = ws.spaces()[1].id;
        let ids = (0..3)
            .map(|i| {
                ws.open_tab(
                    a,
                    Tab::new(format!("https://a{i}.test")),
                    Placement::SectionEnd(Section::Unpinned),
                    true,
                )
                .expect("space exists")
            })
            .collect();
        (ws, a, b, ids)
    }

    #[test]
    fn spaces_keep_independent_active_tabs() {
        let (mut ws, a, b, ids) = workspace_with_tabs();
        let tab_b = ws
            .open_tab(b, Tab::new("https://b.test"), Placement::SectionEnd(Section::Unpinned), true)
            .expect("space exists");
        ws.activate_tab(ids[0]);
        assert_eq!(ws.active_space_id(), a);
        assert!(ws.switch_space(b));
        assert_eq!(ws.active_tab_id(), Some(tab_b));
        assert!(ws.switch_space(a));
        assert_eq!(ws.active_tab_id(), Some(ids[0]));
    }

    #[test]
    fn close_and_reopen_restores_position_and_activation() {
        let (mut ws, a, _, ids) = workspace_with_tabs();
        ws.activate_tab(ids[1]);
        let closed = ws.close_tab(ids[1]).expect("tab exists");
        assert_eq!(closed.space, a);
        assert_eq!(closed.next_active, Some(ids[2]));
        assert_eq!(ws.reopen_closed_tab(), Some(ids[1]));
        assert_eq!(ws.active_space().strip.ordered_tab_ids(), ids);
        assert_eq!(ws.active_tab_id(), Some(ids[1]));
    }

    #[test]
    fn move_tab_between_spaces() {
        let (mut ws, a, b, ids) = workspace_with_tabs();
        assert!(ws.move_tab_to_space(ids[0], b));
        assert_eq!(ws.space_of_tab(ids[0]), Some(b));
        assert_eq!(ws.space(a).map(|s| s.strip.len()), Some(2));
    }

    #[test]
    fn move_group_between_spaces() {
        let (mut ws, a, b, ids) = workspace_with_tabs();
        let group = ws
            .space_mut(a)
            .expect("space")
            .strip
            .create_group("Docs", AccentColor::Ocean, &[ids[0], ids[1]]);
        assert!(ws.move_group_to_space(group, a, b));
        assert_eq!(ws.space(b).map(|s| s.strip.len()), Some(2));
        assert!(ws.space(b).and_then(|s| s.strip.group(group)).is_some());
    }

    #[test]
    fn delete_space_switches_active_and_keeps_last() {
        let (mut ws, a, b, _) = workspace_with_tabs();
        ws.switch_space(b);
        assert!(ws.delete_space(b).is_some());
        assert_eq!(ws.active_space_id(), a);
        assert!(ws.delete_space(a).is_none(), "last space must remain");
    }

    #[test]
    fn favorites_are_global_and_unique() {
        let (mut ws, _, b, ids) = workspace_with_tabs();
        let fav = ws.favorite_from_tab(ids[0]).expect("tab exists");
        assert!(ws.add_favorite("https://a0.test", "dup", None).is_none());
        let fav_tab = ws.favorites()[0].tab.id;
        ws.switch_space(b);
        assert!(ws.activate_tab(fav_tab));
        assert_eq!(ws.active_space_id(), b, "favorites open in the current space");
        assert!(ws.remove_favorite(fav).is_some());
        assert!(ws.tab(fav_tab).is_none());
    }

    #[test]
    fn adjacent_space_does_not_wrap() {
        let (ws, _, b, _) = workspace_with_tabs();
        assert_eq!(ws.adjacent_space(true), Some(b));
        assert_eq!(ws.adjacent_space(false), None);
    }

    #[test]
    fn workspace_serializes_round_trip() {
        let (ws, _, _, _) = workspace_with_tabs();
        let json = serde_json::to_string(&ws).expect("serialize");
        let back: Workspace = serde_json::from_str(&json).expect("deserialize");
        assert_eq!(back.spaces(), ws.spaces());
    }
}

//! Tab organization for a single space: pinned tabs, regular tabs and
//! named groups, with identity-based placement so drag-and-drop and keyboard
//! moves never act on stale indices.
//!
//! A [`TabStrip`] has two sections. Each section is an ordered list of
//! [`Item`]s, where an item is either a top-level tab or a group that holds
//! its own ordered list of tabs. Groups never nest.

use std::collections::HashMap;

use curio_core::{AccentColor, GroupId, Tab, TabGroup, TabId};
use serde::{Deserialize, Serialize};

/// One of the two sidebar sections of a space.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Section {
    /// Pinned tabs and folders, kept across sessions like bookmarks.
    Pinned,
    /// Everyday tabs.
    Unpinned,
}

/// A top-level entry of a section.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", tag = "kind", content = "id")]
pub enum Item {
    Tab(TabId),
    Group(GroupId),
}

/// Where a tab is inserted or moved to. Positions are expressed relative to
/// other items so they remain valid while the moved tab is detached.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Placement {
    /// First position of a section.
    SectionStart(Section),
    /// Last position of a section.
    SectionEnd(Section),
    /// Immediately before a tab, inside the same group if it has one.
    BeforeTab(TabId),
    /// Immediately after a tab, inside the same group if it has one.
    AfterTab(TabId),
    /// Top-level, immediately before a group.
    BeforeGroup(GroupId),
    /// Top-level, immediately after a group.
    AfterGroup(GroupId),
    /// Inside a group at the given index (clamped), or at its end for `None`.
    InGroup(GroupId, Option<usize>),
}

/// Where a group is moved to.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GroupPlacement {
    SectionStart(Section),
    SectionEnd(Section),
    BeforeItem(Item),
    AfterItem(Item),
}

/// A tab's position, as reported by [`TabStrip::location_of`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Location {
    pub section: Section,
    pub group: Option<GroupId>,
    /// Index within the group's tabs when `group` is set, otherwise within
    /// the section's items.
    pub index: usize,
}

/// A tab removed from a strip, with enough context to put it back.
#[derive(Debug, Clone, PartialEq)]
pub struct RemovedTab {
    pub tab: Tab,
    pub restore_at: Placement,
}

/// A row of the flattened sidebar, in display order.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Row {
    Tab {
        id: TabId,
        section: Section,
        group: Option<GroupId>,
    },
    Group {
        id: GroupId,
        section: Section,
    },
}

/// The tabs and groups of one space.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct TabStrip {
    tabs: HashMap<TabId, Tab>,
    groups: HashMap<GroupId, TabGroup>,
    pinned: Vec<Item>,
    unpinned: Vec<Item>,
}

impl TabStrip {
    /// Creates an empty strip.
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// Rebuilds a strip from persisted parts, dropping dangling references
    /// so a corrupted database cannot produce an inconsistent strip.
    #[must_use]
    pub fn from_parts(
        tabs: Vec<Tab>,
        groups: Vec<TabGroup>,
        pinned: Vec<Item>,
        unpinned: Vec<Item>,
    ) -> Self {
        let tabs: HashMap<TabId, Tab> = tabs.into_iter().map(|t| (t.id, t)).collect();
        let mut groups: HashMap<GroupId, TabGroup> =
            groups.into_iter().map(|g| (g.id, g)).collect();
        let mut seen = std::collections::HashSet::new();
        for group in groups.values_mut() {
            group
                .tabs
                .retain(|id| tabs.contains_key(id) && seen.insert(*id));
        }
        let keep = |items: Vec<Item>, seen: &mut std::collections::HashSet<TabId>| {
            let mut seen_groups = std::collections::HashSet::new();
            items
                .into_iter()
                .filter(|item| match item {
                    Item::Tab(id) => tabs.contains_key(id) && seen.insert(*id),
                    Item::Group(id) => groups.contains_key(id) && seen_groups.insert(*id),
                })
                .collect::<Vec<_>>()
        };
        let pinned = keep(pinned, &mut seen);
        let unpinned = keep(unpinned, &mut seen);
        let mut strip = Self {
            tabs,
            groups,
            pinned,
            unpinned,
        };
        // Tabs that are not referenced anywhere are appended so no data is lost.
        let orphans: Vec<TabId> = strip
            .tabs
            .keys()
            .filter(|id| !seen.contains(id))
            .copied()
            .collect();
        strip.unpinned.extend(orphans.into_iter().map(Item::Tab));
        // Groups not referenced by either section become unpinned.
        let referenced: std::collections::HashSet<GroupId> = strip
            .pinned
            .iter()
            .chain(&strip.unpinned)
            .filter_map(|item| match item {
                Item::Group(id) => Some(*id),
                Item::Tab(_) => None,
            })
            .collect();
        let unreferenced: Vec<GroupId> = strip
            .groups
            .keys()
            .filter(|id| !referenced.contains(id))
            .copied()
            .collect();
        strip
            .unpinned
            .extend(unreferenced.into_iter().map(Item::Group));
        strip
    }

    /// Number of tabs, including grouped ones.
    #[must_use]
    pub fn len(&self) -> usize {
        self.tabs.len()
    }

    /// Returns `true` when the strip has no tabs.
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.tabs.is_empty()
    }

    /// Looks up a tab.
    #[must_use]
    pub fn tab(&self, id: TabId) -> Option<&Tab> {
        self.tabs.get(&id)
    }

    /// Looks up a tab for mutation.
    pub fn tab_mut(&mut self, id: TabId) -> Option<&mut Tab> {
        self.tabs.get_mut(&id)
    }

    /// Returns `true` if the strip owns `id`.
    #[must_use]
    pub fn contains(&self, id: TabId) -> bool {
        self.tabs.contains_key(&id)
    }

    /// Iterates over every tab in unspecified order.
    pub fn tabs(&self) -> impl Iterator<Item = &Tab> {
        self.tabs.values()
    }

    /// Looks up a group.
    #[must_use]
    pub fn group(&self, id: GroupId) -> Option<&TabGroup> {
        self.groups.get(&id)
    }

    /// Iterates over every group in unspecified order.
    pub fn groups(&self) -> impl Iterator<Item = &TabGroup> {
        self.groups.values()
    }

    /// The items of a section, in order.
    #[must_use]
    pub fn items(&self, section: Section) -> &[Item] {
        match section {
            Section::Pinned => &self.pinned,
            Section::Unpinned => &self.unpinned,
        }
    }

    fn items_mut(&mut self, section: Section) -> &mut Vec<Item> {
        match section {
            Section::Pinned => &mut self.pinned,
            Section::Unpinned => &mut self.unpinned,
        }
    }

    /// Finds where a tab currently lives.
    #[must_use]
    pub fn location_of(&self, id: TabId) -> Option<Location> {
        for section in [Section::Pinned, Section::Unpinned] {
            for (index, item) in self.items(section).iter().enumerate() {
                match item {
                    Item::Tab(tab) if *tab == id => {
                        return Some(Location {
                            section,
                            group: None,
                            index,
                        });
                    }
                    Item::Group(group_id) => {
                        if let Some(group) = self.groups.get(group_id)
                            && let Some(index) = group.tabs.iter().position(|t| *t == id)
                        {
                            return Some(Location {
                                section,
                                group: Some(*group_id),
                                index,
                            });
                        }
                    }
                    Item::Tab(_) => {}
                }
            }
        }
        None
    }

    /// Finds the section and index of a group.
    #[must_use]
    pub fn group_location(&self, id: GroupId) -> Option<(Section, usize)> {
        [Section::Pinned, Section::Unpinned]
            .into_iter()
            .find_map(|section| {
                self.items(section)
                    .iter()
                    .position(|item| *item == Item::Group(id))
                    .map(|index| (section, index))
            })
    }

    /// Returns `true` if the tab is in the pinned section.
    #[must_use]
    pub fn is_pinned(&self, id: TabId) -> bool {
        self.location_of(id)
            .is_some_and(|loc| loc.section == Section::Pinned)
    }

    /// Inserts a tab. If the placement refers to something that no longer
    /// exists, the tab is appended to the unpinned section instead.
    pub fn insert(&mut self, tab: Tab, placement: Placement) -> TabId {
        let id = tab.id;
        self.tabs.insert(id, tab);
        self.attach(id, placement);
        id
    }

    fn attach(&mut self, id: TabId, placement: Placement) {
        let fallback = Placement::SectionEnd(Section::Unpinned);
        match placement {
            Placement::SectionStart(section) => self.items_mut(section).insert(0, Item::Tab(id)),
            Placement::SectionEnd(section) => self.items_mut(section).push(Item::Tab(id)),
            Placement::BeforeTab(anchor) | Placement::AfterTab(anchor) => {
                let after = matches!(placement, Placement::AfterTab(_));
                match self.location_of(anchor) {
                    Some(Location {
                        group: Some(group),
                        index,
                        ..
                    }) => {
                        if let Some(group) = self.groups.get_mut(&group) {
                            group.tabs.insert(index + usize::from(after), id);
                        }
                    }
                    Some(Location {
                        section,
                        group: None,
                        index,
                    }) => self
                        .items_mut(section)
                        .insert(index + usize::from(after), Item::Tab(id)),
                    None => self.attach(id, fallback),
                }
            }
            Placement::BeforeGroup(anchor) | Placement::AfterGroup(anchor) => {
                let after = matches!(placement, Placement::AfterGroup(_));
                match self.group_location(anchor) {
                    Some((section, index)) => self
                        .items_mut(section)
                        .insert(index + usize::from(after), Item::Tab(id)),
                    None => self.attach(id, fallback),
                }
            }
            Placement::InGroup(group_id, index) => match self.groups.get_mut(&group_id) {
                Some(group) => {
                    let index = index.unwrap_or(group.tabs.len()).min(group.tabs.len());
                    group.tabs.insert(index, id);
                }
                None => self.attach(id, fallback),
            },
        }
    }

    /// Detaches a tab from its section or group without dropping its data,
    /// returning a placement that would put it back.
    fn detach(&mut self, id: TabId) -> Option<Placement> {
        let location = self.location_of(id)?;
        let restore_at = self.restore_placement(location);
        match location.group {
            Some(group) => {
                if let Some(group) = self.groups.get_mut(&group) {
                    group.tabs.remove(location.index);
                }
            }
            None => {
                self.items_mut(location.section).remove(location.index);
            }
        }
        Some(restore_at)
    }

    fn restore_placement(&self, location: Location) -> Placement {
        match location.group {
            Some(group_id) => {
                let group = &self.groups[&group_id];
                match location.index.checked_sub(1).and_then(|i| group.tabs.get(i)) {
                    Some(prev) => Placement::AfterTab(*prev),
                    None => Placement::InGroup(group_id, Some(0)),
                }
            }
            None => {
                let items = self.items(location.section);
                let prev = location.index.checked_sub(1).and_then(|i| items.get(i));
                match prev {
                    Some(Item::Tab(prev)) => Placement::AfterTab(*prev),
                    Some(Item::Group(group)) => Placement::AfterGroup(*group),
                    None => Placement::SectionStart(location.section),
                }
            }
        }
    }

    /// Removes a tab, returning it with a placement to restore it later.
    pub fn remove(&mut self, id: TabId) -> Option<RemovedTab> {
        let restore_at = self.detach(id)?;
        let tab = self.tabs.remove(&id)?;
        Some(RemovedTab { tab, restore_at })
    }

    /// Moves a tab. Moving a tab relative to itself is a no-op.
    pub fn move_tab(&mut self, id: TabId, placement: Placement) -> bool {
        if !self.contains(id) {
            return false;
        }
        if matches!(placement, Placement::BeforeTab(a) | Placement::AfterTab(a) if a == id) {
            return false;
        }
        if self.detach(id).is_none() {
            return false;
        }
        self.attach(id, placement);
        true
    }

    /// Pins a tab: moves it (out of any group) to the end of the pinned
    /// section and remembers its current URL as its home.
    pub fn pin(&mut self, id: TabId) -> bool {
        if self.is_pinned(id) {
            return false;
        }
        if let Some(tab) = self.tabs.get_mut(&id) {
            tab.home_url = Some(tab.url.clone());
        }
        self.move_tab(id, Placement::SectionEnd(Section::Pinned))
    }

    /// Unpins a tab, moving it to the top of the unpinned section.
    pub fn unpin(&mut self, id: TabId) -> bool {
        if !self.is_pinned(id) {
            return false;
        }
        if let Some(tab) = self.tabs.get_mut(&id) {
            tab.home_url = None;
        }
        self.move_tab(id, Placement::SectionStart(Section::Unpinned))
    }

    /// Creates a group at the position of the first of `members` (or at the
    /// end of the unpinned section when empty) and moves the members into it.
    pub fn create_group(
        &mut self,
        name: impl Into<String>,
        color: AccentColor,
        members: &[TabId],
    ) -> GroupId {
        let group = TabGroup::new(name, color);
        let group_id = group.id;
        let anchor = members
            .iter()
            .find_map(|id| self.location_of(*id).map(|loc| (*id, loc)));
        let (section, index) = match anchor {
            Some((
                _,
                Location {
                    section,
                    group: None,
                    index,
                },
            )) => (section, index),
            Some((
                _,
                Location {
                    section,
                    group: Some(parent),
                    ..
                },
            )) => (
                section,
                self.group_location(parent).map_or(0, |(_, index)| index + 1),
            ),
            None => (Section::Unpinned, self.unpinned.len()),
        };
        self.groups.insert(group_id, group);
        let index = index.min(self.items(section).len());
        self.items_mut(section).insert(index, Item::Group(group_id));
        for member in members {
            self.move_tab(*member, Placement::InGroup(group_id, None));
        }
        group_id
    }

    /// Renames a group. Blank names are ignored.
    pub fn rename_group(&mut self, id: GroupId, name: &str) -> bool {
        let name = name.trim();
        match self.groups.get_mut(&id) {
            Some(group) if !name.is_empty() => {
                name.clone_into(&mut group.name);
                true
            }
            _ => false,
        }
    }

    /// Changes a group's color.
    pub fn set_group_color(&mut self, id: GroupId, color: AccentColor) -> bool {
        self.groups
            .get_mut(&id)
            .map(|group| group.color = color)
            .is_some()
    }

    /// Collapses or expands a group.
    pub fn set_group_collapsed(&mut self, id: GroupId, collapsed: bool) -> bool {
        self.groups
            .get_mut(&id)
            .map(|group| group.collapsed = collapsed)
            .is_some()
    }

    /// Deletes a group. With `keep_tabs`, its tabs are spliced into the
    /// section where the group was; otherwise they are removed and returned.
    pub fn delete_group(&mut self, id: GroupId, keep_tabs: bool) -> Vec<Tab> {
        let Some((section, index)) = self.group_location(id) else {
            return Vec::new();
        };
        let Some(group) = self.groups.remove(&id) else {
            return Vec::new();
        };
        let items = self.items_mut(section);
        items.remove(index);
        if keep_tabs {
            for (offset, tab) in group.tabs.iter().enumerate() {
                items.insert(index + offset, Item::Tab(*tab));
            }
            Vec::new()
        } else {
            group
                .tabs
                .iter()
                .filter_map(|tab| self.tabs.remove(tab))
                .collect()
        }
    }

    /// Moves a group to a new top-level position.
    pub fn move_group(&mut self, id: GroupId, placement: GroupPlacement) -> bool {
        if matches!(placement, GroupPlacement::BeforeItem(Item::Group(g)) | GroupPlacement::AfterItem(Item::Group(g)) if g == id)
        {
            return false;
        }
        let Some((section, index)) = self.group_location(id) else {
            return false;
        };
        self.items_mut(section).remove(index);
        let item = Item::Group(id);
        let (target, at) = match placement {
            GroupPlacement::SectionStart(s) => (s, Some(0)),
            GroupPlacement::SectionEnd(s) => (s, None),
            GroupPlacement::BeforeItem(anchor) | GroupPlacement::AfterItem(anchor) => {
                let after = matches!(placement, GroupPlacement::AfterItem(_));
                let found = [Section::Pinned, Section::Unpinned]
                    .into_iter()
                    .find_map(|s| {
                        self.items(s)
                            .iter()
                            .position(|i| *i == anchor)
                            .map(|i| (s, i))
                    })
                    .or_else(|| match anchor {
                        // Anchoring on a grouped tab means "next to its group".
                        Item::Tab(tab) => self.location_of(tab).and_then(|loc| {
                            loc.group
                                .and_then(|g| self.group_location(g))
                        }),
                        Item::Group(_) => None,
                    });
                match found {
                    Some((s, i)) => (s, Some(i + usize::from(after))),
                    None => (section, Some(index)),
                }
            }
        };
        let items = self.items_mut(target);
        match at {
            Some(i) => items.insert(i.min(items.len()), item),
            None => items.push(item),
        }
        true
    }

    /// Removes a group and its tabs so they can move to another space.
    pub fn take_group(&mut self, id: GroupId) -> Option<(TabGroup, Vec<Tab>, Section)> {
        let (section, index) = self.group_location(id)?;
        self.items_mut(section).remove(index);
        let group = self.groups.remove(&id)?;
        let tabs = group
            .tabs
            .iter()
            .filter_map(|tab| self.tabs.remove(tab))
            .collect();
        Some((group, tabs, section))
    }

    /// Adds a group (with its tabs) at the end of `section`. Tab membership
    /// is taken from `group.tabs`; tabs not listed there are appended.
    pub fn insert_group(&mut self, mut group: TabGroup, tabs: Vec<Tab>, section: Section) -> GroupId {
        let id = group.id;
        for tab in tabs {
            if !group.tabs.contains(&tab.id) {
                group.tabs.push(tab.id);
            }
            self.tabs.insert(tab.id, tab);
        }
        group.tabs.retain(|t| self.tabs.contains_key(t));
        self.groups.insert(id, group);
        self.items_mut(section).push(Item::Group(id));
        id
    }

    /// Every tab id in display order (pinned first, groups expanded).
    #[must_use]
    pub fn ordered_tab_ids(&self) -> Vec<TabId> {
        let mut out = Vec::with_capacity(self.tabs.len());
        for section in [Section::Pinned, Section::Unpinned] {
            for item in self.items(section) {
                match item {
                    Item::Tab(id) => out.push(*id),
                    Item::Group(group) => {
                        if let Some(group) = self.groups.get(group) {
                            out.extend(group.tabs.iter().copied());
                        }
                    }
                }
            }
        }
        out
    }

    /// Flattened rows for rendering. Tabs inside collapsed groups are
    /// omitted unless they are `always_show` (typically the active tab, which
    /// stays visible under its collapsed folder as in Arc).
    #[must_use]
    pub fn rows(&self, always_show: Option<TabId>) -> Vec<Row> {
        let mut rows = Vec::with_capacity(self.tabs.len() + self.groups.len());
        for section in [Section::Pinned, Section::Unpinned] {
            for item in self.items(section) {
                match item {
                    Item::Tab(id) => rows.push(Row::Tab {
                        id: *id,
                        section,
                        group: None,
                    }),
                    Item::Group(group_id) => {
                        let Some(group) = self.groups.get(group_id) else {
                            continue;
                        };
                        rows.push(Row::Group {
                            id: *group_id,
                            section,
                        });
                        for tab in &group.tabs {
                            if !group.collapsed || Some(*tab) == always_show {
                                rows.push(Row::Tab {
                                    id: *tab,
                                    section,
                                    group: Some(*group_id),
                                });
                            }
                        }
                    }
                }
            }
        }
        rows
    }

    /// The tab to activate after `closing` is closed: the next tab in display
    /// order, or the previous one when it was last.
    #[must_use]
    pub fn neighbor_for_close(&self, closing: TabId) -> Option<TabId> {
        let order = self.ordered_tab_ids();
        let index = order.iter().position(|id| *id == closing)?;
        order
            .get(index + 1)
            .or_else(|| index.checked_sub(1).and_then(|i| order.get(i)))
            .copied()
    }

    /// Persisted parts, for storage.
    #[must_use]
    pub fn parts(&self) -> (Vec<&Tab>, Vec<&TabGroup>, &[Item], &[Item]) {
        (
            self.tabs.values().collect(),
            self.groups.values().collect(),
            &self.pinned,
            &self.unpinned,
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn strip_with(n: usize) -> (TabStrip, Vec<TabId>) {
        let mut strip = TabStrip::new();
        let ids = (0..n)
            .map(|i| {
                strip.insert(
                    Tab::new(format!("https://site{i}.test")),
                    Placement::SectionEnd(Section::Unpinned),
                )
            })
            .collect();
        (strip, ids)
    }

    #[test]
    fn insert_and_order() {
        let (mut strip, ids) = strip_with(3);
        let extra = strip.insert(Tab::default(), Placement::AfterTab(ids[0]));
        assert_eq!(strip.ordered_tab_ids(), vec![ids[0], extra, ids[1], ids[2]]);
    }

    #[test]
    fn pin_and_unpin_move_between_sections() {
        let (mut strip, ids) = strip_with(3);
        assert!(strip.pin(ids[2]));
        assert!(strip.is_pinned(ids[2]));
        assert_eq!(strip.ordered_tab_ids()[0], ids[2]);
        assert_eq!(
            strip.tab(ids[2]).and_then(|t| t.home_url.clone()).as_deref(),
            Some("https://site2.test")
        );
        assert!(strip.unpin(ids[2]));
        assert!(!strip.is_pinned(ids[2]));
        assert_eq!(strip.ordered_tab_ids(), vec![ids[2], ids[0], ids[1]]);
    }

    #[test]
    fn remove_and_restore_returns_tab_to_same_spot() {
        let (mut strip, ids) = strip_with(3);
        let removed = strip.remove(ids[1]).expect("tab exists");
        assert_eq!(removed.restore_at, Placement::AfterTab(ids[0]));
        strip.insert(removed.tab, removed.restore_at);
        assert_eq!(strip.ordered_tab_ids(), ids);
    }

    #[test]
    fn groups_collect_members_and_collapse() {
        let (mut strip, ids) = strip_with(4);
        let group = strip.create_group("Research", AccentColor::Ocean, &[ids[1], ids[3]]);
        assert_eq!(strip.ordered_tab_ids(), vec![ids[0], ids[1], ids[3], ids[2]]);
        assert_eq!(strip.location_of(ids[3]).and_then(|l| l.group), Some(group));

        strip.set_group_collapsed(group, true);
        let rows = strip.rows(None);
        assert_eq!(rows.len(), 3); // tab0, group header, tab2
        let rows = strip.rows(Some(ids[3]));
        assert!(rows.contains(&Row::Tab {
            id: ids[3],
            section: Section::Unpinned,
            group: Some(group)
        }));
    }

    #[test]
    fn delete_group_keeping_tabs_splices_them_in_place() {
        let (mut strip, ids) = strip_with(3);
        let group = strip.create_group("G", AccentColor::Sage, &[ids[1], ids[2]]);
        let removed = strip.delete_group(group, true);
        assert!(removed.is_empty());
        assert_eq!(strip.ordered_tab_ids(), ids);
        assert!(strip.group(group).is_none());
    }

    #[test]
    fn delete_group_with_tabs_returns_them() {
        let (mut strip, ids) = strip_with(3);
        let group = strip.create_group("G", AccentColor::Sage, &[ids[0], ids[1]]);
        let removed = strip.delete_group(group, false);
        assert_eq!(removed.len(), 2);
        assert_eq!(strip.ordered_tab_ids(), vec![ids[2]]);
    }

    #[test]
    fn drag_tab_into_and_out_of_group() {
        let (mut strip, ids) = strip_with(3);
        let group = strip.create_group("G", AccentColor::Rose, &[ids[0]]);
        assert!(strip.move_tab(ids[2], Placement::InGroup(group, Some(0))));
        assert_eq!(strip.group(group).map(|g| g.tabs.clone()), Some(vec![ids[2], ids[0]]));
        assert!(strip.move_tab(ids[2], Placement::AfterGroup(group)));
        assert_eq!(strip.location_of(ids[2]).and_then(|l| l.group), None);
        assert_eq!(strip.ordered_tab_ids(), vec![ids[0], ids[2], ids[1]]);
    }

    #[test]
    fn moving_relative_to_self_is_noop() {
        let (mut strip, ids) = strip_with(2);
        assert!(!strip.move_tab(ids[0], Placement::AfterTab(ids[0])));
        assert_eq!(strip.ordered_tab_ids(), ids);
    }

    #[test]
    fn reorder_groups_and_move_between_sections() {
        let (mut strip, ids) = strip_with(3);
        let a = strip.create_group("A", AccentColor::Iris, &[ids[0]]);
        let b = strip.create_group("B", AccentColor::Iris, &[ids[2]]);
        assert!(strip.move_group(b, GroupPlacement::BeforeItem(Item::Group(a))));
        assert_eq!(strip.ordered_tab_ids(), vec![ids[2], ids[0], ids[1]]);
        assert!(strip.move_group(a, GroupPlacement::SectionEnd(Section::Pinned)));
        assert!(strip.is_pinned(ids[0]));
    }

    #[test]
    fn take_and_insert_group_moves_whole_group() {
        let (mut strip, ids) = strip_with(3);
        let group = strip.create_group("Move me", AccentColor::Amber, &[ids[0], ids[1]]);
        let (g, tabs, section) = strip.take_group(group).expect("group exists");
        assert_eq!(strip.len(), 1);
        let mut other = TabStrip::new();
        other.insert_group(g, tabs, section);
        assert_eq!(other.ordered_tab_ids(), vec![ids[0], ids[1]]);
    }

    #[test]
    fn neighbor_prefers_next_then_previous() {
        let (strip, ids) = strip_with(3);
        assert_eq!(strip.neighbor_for_close(ids[1]), Some(ids[2]));
        assert_eq!(strip.neighbor_for_close(ids[2]), Some(ids[1]));
    }

    #[test]
    fn from_parts_repairs_dangling_references() {
        let tab = Tab::new("https://a.test");
        let orphan = Tab::new("https://b.test");
        let strip = TabStrip::from_parts(
            vec![tab.clone(), orphan.clone()],
            vec![],
            vec![Item::Tab(TabId::new()), Item::Tab(tab.id), Item::Tab(tab.id)],
            vec![Item::Group(GroupId::new())],
        );
        assert_eq!(strip.ordered_tab_ids(), vec![tab.id, orphan.id]);
    }

    #[test]
    fn strip_serializes_round_trip() {
        let (mut strip, ids) = strip_with(2);
        strip.create_group("G", AccentColor::Plum, &[ids[1]]);
        let json = serde_json::to_string(&strip).expect("serialize");
        let back: TabStrip = serde_json::from_str(&json).expect("deserialize");
        assert_eq!(back, strip);
    }
}

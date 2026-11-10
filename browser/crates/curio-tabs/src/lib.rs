//! Tab organization for a single space: pinned tabs, regular tabs and
//! named groups, with identity-based placement so drag-and-drop and keyboard
//! moves never act on stale indices.
//!
//! A [`TabStrip`] has two sections. Each section is an ordered list of
//! [`Item`]s, where an item is either a top-level tab or a group that holds
//! its own ordered list of tabs. Groups never nest.
//!
//! Tabs can also be shown together in a [`TabSplit`] (split view). A split's
//! tabs stay ordinary tabs of the strip, but they are always kept next to
//! each other, in pane order, in the same section or folder. Moving any of
//! them moves the whole split, so a split lives in exactly one place.

use std::collections::{HashMap, HashSet};

use curio_core::{AccentColor, GroupId, SplitId, SplitOrientation, Tab, TabGroup, TabId, TabSplit};
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
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
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

/// A group taken out of a strip with everything needed to put it in
/// another one: its tabs and the splits among them.
#[derive(Debug, Clone, PartialEq)]
pub struct TakenGroup {
    pub group: TabGroup,
    pub tabs: Vec<Tab>,
    pub splits: Vec<TabSplit>,
    pub section: Section,
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
    /// A split view, shown as one row in place of its tabs.
    Split {
        id: SplitId,
        section: Section,
        group: Option<GroupId>,
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
    splits: HashMap<SplitId, TabSplit>,
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
        splits: Vec<TabSplit>,
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
            splits: splits.into_iter().map(|s| (s.id, s)).collect(),
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
        strip.repair_splits();
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

    /// Where a new tab opened from `anchor` goes: right after it when it's
    /// a regular tab, right after its folder when it's in a regular folder,
    /// and at the top of the unpinned section otherwise. New tabs never land
    /// inside a folder or in the pinned section.
    #[must_use]
    pub fn placement_for_new_tab(&self, anchor: Option<TabId>) -> Placement {
        // A tab opened from a split goes after the whole split.
        let anchor = anchor.map(|id| {
            self.split_of(id)
                .and_then(|split| split.tabs.last().copied())
                .unwrap_or(id)
        });
        let location = anchor.and_then(|id| self.location_of(id).map(|loc| (id, loc)));
        match location {
            Some((id, loc)) if loc.section == Section::Unpinned => match loc.group {
                Some(group) => Placement::AfterGroup(group),
                None => Placement::AfterTab(id),
            },
            _ => Placement::SectionStart(Section::Unpinned),
        }
    }

    /// Whether a tab is kept when closed: pinned tabs and tabs in a folder.
    /// Closing a saved tab unloads it and resets it to its home URL.
    #[must_use]
    pub fn is_saved(&self, id: TabId) -> bool {
        self.location_of(id)
            .is_some_and(|loc| loc.section == Section::Pinned || loc.group.is_some())
    }

    /// Saved tabs remember the URL they were saved with as their home; a
    /// tab that leaves the pinned section and every folder forgets it.
    fn sync_home(&mut self, id: TabId) {
        let saved = self.is_saved(id);
        if let Some(tab) = self.tabs.get_mut(&id) {
            if !saved {
                tab.home_url = None;
            } else if tab.home_url.is_none() {
                tab.home_url = Some(tab.url.clone());
            }
        }
    }

    /// Inserts a tab. If the placement refers to something that no longer
    /// exists, the tab is appended to the unpinned section instead.
    pub fn insert(&mut self, tab: Tab, placement: Placement) -> TabId {
        let id = tab.id;
        self.tabs.insert(id, tab);
        self.attach(id, placement);
        self.sync_home(id);
        self.repair_splits();
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
                match location
                    .index
                    .checked_sub(1)
                    .and_then(|i| group.tabs.get(i))
                {
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
        self.repair_splits();
        Some(RemovedTab { tab, restore_at })
    }

    /// Moves a tab. Moving a tab relative to itself is a no-op.
    ///
    /// Moving a tab that is part of a split moves the whole split: its first
    /// pane goes to `placement` and the others follow it.
    pub fn move_tab(&mut self, id: TabId, placement: Placement) -> bool {
        if !self.contains(id) {
            return false;
        }
        let (id, members) = match self.split_of(id) {
            Some(split) => (split.tabs[0], split.tabs.clone()),
            None => (id, vec![id]),
        };
        if matches!(placement, Placement::BeforeTab(a) | Placement::AfterTab(a) if members.contains(&a))
        {
            return false;
        }
        if self.detach(id).is_none() {
            return false;
        }
        self.attach(id, placement);
        self.sync_home(id);
        self.repair_splits();
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
                self.group_location(parent)
                    .map_or(0, |(_, index)| index + 1),
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
        let removed = if keep_tabs {
            for (offset, tab) in group.tabs.iter().enumerate() {
                items.insert(index + offset, Item::Tab(*tab));
            }
            for tab in &group.tabs {
                self.sync_home(*tab);
            }
            Vec::new()
        } else {
            group
                .tabs
                .iter()
                .filter_map(|tab| self.tabs.remove(tab))
                .collect()
        };
        self.repair_splits();
        removed
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
                        Item::Tab(tab) => self
                            .location_of(tab)
                            .and_then(|loc| loc.group.and_then(|g| self.group_location(g))),
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
        // Dropping a folder next to a split's inner tab would separate it.
        self.repair_splits();
        true
    }

    /// Removes a group with its tabs and splits so they can move to another
    /// space.
    pub fn take_group(&mut self, id: GroupId) -> Option<TakenGroup> {
        let (section, index) = self.group_location(id)?;
        self.items_mut(section).remove(index);
        let group = self.groups.remove(&id)?;
        let tabs: Vec<Tab> = group
            .tabs
            .iter()
            .filter_map(|tab| self.tabs.remove(tab))
            .collect();
        let inside: Vec<SplitId> = self
            .splits
            .values()
            .filter(|split| split.tabs.iter().any(|t| group.tabs.contains(t)))
            .map(|split| split.id)
            .collect();
        let splits = inside
            .into_iter()
            .filter_map(|split| self.splits.remove(&split))
            .collect();
        self.repair_splits();
        Some(TakenGroup {
            group,
            tabs,
            splits,
            section,
        })
    }

    /// Adds a group (with its tabs and splits) at the end of its section.
    /// Tab membership is taken from `group.tabs`; tabs not listed there are
    /// appended.
    pub fn insert_group(&mut self, taken: TakenGroup) -> GroupId {
        let TakenGroup {
            mut group,
            tabs,
            splits,
            section,
        } = taken;
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
        self.splits.extend(splits.into_iter().map(|s| (s.id, s)));
        self.repair_splits();
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
    ///
    /// A split is one [`Row::Split`] where its first tab would be; its other
    /// tabs get no row of their own.
    #[must_use]
    pub fn rows(&self, always_show: Option<TabId>) -> Vec<Row> {
        let mut rows = Vec::with_capacity(self.tabs.len() + self.groups.len());
        // The split the always-shown tab belongs to stays visible with it.
        let always_split = always_show.and_then(|id| self.split_of(id)).map(|s| s.id);
        let row_for = |id: TabId, section: Section, group: Option<GroupId>| match self.split_of(id)
        {
            Some(split) if split.tabs[0] == id => Some(Row::Split {
                id: split.id,
                section,
                group,
            }),
            Some(_) => None,
            None => Some(Row::Tab { id, section, group }),
        };
        for section in [Section::Pinned, Section::Unpinned] {
            for item in self.items(section) {
                match item {
                    Item::Tab(id) => rows.extend(row_for(*id, section, None)),
                    Item::Group(group_id) => {
                        let Some(group) = self.groups.get(group_id) else {
                            continue;
                        };
                        rows.push(Row::Group {
                            id: *group_id,
                            section,
                        });
                        for tab in &group.tabs {
                            let shown = !group.collapsed
                                || Some(*tab) == always_show
                                || (always_split.is_some()
                                    && self.split_of(*tab).map(|s| s.id) == always_split);
                            if shown {
                                rows.extend(row_for(*tab, section, Some(*group_id)));
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

    // ----- Split view ---------------------------------------------------

    /// Every split, in unspecified order.
    pub fn splits(&self) -> impl Iterator<Item = &TabSplit> {
        self.splits.values()
    }

    /// Looks up a split.
    #[must_use]
    pub fn split(&self, id: SplitId) -> Option<&TabSplit> {
        self.splits.get(&id)
    }

    /// The split a tab is shown in, if any.
    #[must_use]
    pub fn split_of(&self, tab: TabId) -> Option<&TabSplit> {
        // Splits are few (a handful per space), so a scan beats keeping a
        // reverse index in sync.
        self.splits.values().find(|split| split.contains(tab))
    }

    /// Shows `tabs` side by side. They are taken out of any split they were
    /// in and gathered next to the first of them, in its section or folder.
    /// Tabs the strip doesn't own are ignored; returns `None` unless at
    /// least two remain.
    pub fn create_split(
        &mut self,
        tabs: &[TabId],
        orientation: SplitOrientation,
    ) -> Option<SplitId> {
        let members: Vec<TabId> = tabs.iter().copied().filter(|t| self.contains(*t)).collect();
        let split = TabSplit::new(&members, orientation);
        if !split.is_valid() {
            return None;
        }
        for tab in &split.tabs {
            self.detach_from_split(*tab);
        }
        let id = split.id;
        self.splits.insert(id, split);
        self.repair_splits();
        Some(id)
    }

    /// Adds `tab` to a split as the pane at `index` (clamped to the end).
    /// The tab leaves any other split and moves next to the split's other
    /// tabs.
    pub fn add_to_split(&mut self, split: SplitId, tab: TabId, index: usize) -> bool {
        if !self.contains(tab)
            || self
                .splits
                .get(&split)
                .is_none_or(|s| s.is_full() || s.contains(tab))
        {
            return false;
        }
        self.detach_from_split(tab);
        let added = self
            .splits
            .get_mut(&split)
            .is_some_and(|s| s.add_tab(tab, index));
        self.repair_splits();
        added
    }

    /// Takes a tab out of its split and puts it right after the split. A
    /// split left with one tab is dissolved.
    pub fn remove_from_split(&mut self, tab: TabId) -> bool {
        let Some(last) = self.detach_from_split(tab) else {
            return false;
        };
        if last != tab {
            self.move_tab(tab, Placement::AfterTab(last));
        }
        self.repair_splits();
        true
    }

    /// Dissolves a split; its tabs stay where they are as ordinary tabs.
    pub fn dissolve_split(&mut self, id: SplitId) -> bool {
        self.splits.remove(&id).is_some()
    }

    /// Moves the divider after pane `divider` (see [`TabSplit::resize`]).
    pub fn resize_split(&mut self, id: SplitId, divider: usize, delta: f32) -> bool {
        self.splits
            .get_mut(&id)
            .is_some_and(|split| split.resize(divider, delta))
    }

    /// Gives every pane of a split the same room.
    pub fn equalize_split(&mut self, id: SplitId) -> bool {
        self.splits.get_mut(&id).map(TabSplit::equalize).is_some()
    }

    /// Switches a split between side by side and stacked.
    pub fn flip_split(&mut self, id: SplitId) -> bool {
        self.splits
            .get_mut(&id)
            .map(|split| split.orientation = split.orientation.flipped())
            .is_some()
    }

    /// Takes a tab out of its split without moving it. Returns the split's
    /// last remaining pane (or the tab itself when the split dissolved).
    fn detach_from_split(&mut self, tab: TabId) -> Option<TabId> {
        let id = self.split_of(tab)?.id;
        let split = self.splits.get_mut(&id)?;
        split.remove_tab(tab);
        if split.is_valid() {
            split.tabs.last().copied()
        } else {
            let last = split.tabs.last().copied();
            self.splits.remove(&id);
            last.or(Some(tab))
        }
    }

    /// Keeps every split consistent with the strip: drops panes whose tabs
    /// are gone (and splits left too small), a tab in two splits stays in
    /// the first, and each split's tabs are gathered after its first pane,
    /// in pane order, in the same section or folder.
    fn repair_splits(&mut self) {
        if self.splits.is_empty() {
            return;
        }
        let mut ids: Vec<SplitId> = self.splits.keys().copied().collect();
        ids.sort_unstable();
        let mut seen = HashSet::new();
        for id in &ids {
            let tabs = &self.tabs;
            let Some(split) = self.splits.get_mut(id) else {
                continue;
            };
            let before = split.tabs.len();
            split
                .tabs
                .retain(|t| tabs.contains_key(t) && seen.insert(*t));
            if split.tabs.len() != before {
                split.equalize();
            } else {
                split.normalize();
            }
            if !split.is_valid() {
                self.splits.remove(id);
            }
        }
        for id in ids {
            let Some(members) = self.splits.get(&id).map(|s| s.tabs.clone()) else {
                continue;
            };
            if self.is_contiguous(&members) {
                continue;
            }
            for pair in members.windows(2) {
                let (prev, tab) = (pair[0], pair[1]);
                if self.detach(tab).is_some() {
                    self.attach(tab, Placement::AfterTab(prev));
                    self.sync_home(tab);
                }
            }
        }
    }

    /// Whether `members` sit next to each other, in order, in one container.
    fn is_contiguous(&self, members: &[TabId]) -> bool {
        let Some(first) = members.first().and_then(|t| self.location_of(*t)) else {
            return false;
        };
        members.iter().enumerate().skip(1).all(|(offset, tab)| {
            self.location_of(*tab).is_some_and(|loc| {
                loc.section == first.section
                    && loc.group == first.group
                    && loc.index == first.index + offset
            })
        })
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
            strip
                .tab(ids[2])
                .and_then(|t| t.home_url.clone())
                .as_deref(),
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
        assert_eq!(
            strip.ordered_tab_ids(),
            vec![ids[0], ids[1], ids[3], ids[2]]
        );
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
        assert_eq!(
            strip.group(group).map(|g| g.tabs.clone()),
            Some(vec![ids[2], ids[0]])
        );
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
        let taken = strip.take_group(group).expect("group exists");
        assert_eq!(strip.len(), 1);
        let mut other = TabStrip::new();
        other.insert_group(taken);
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
            vec![
                Item::Tab(TabId::new()),
                Item::Tab(tab.id),
                Item::Tab(tab.id),
            ],
            vec![Item::Group(GroupId::new())],
            vec![],
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

    #[test]
    fn tabs_in_folders_are_saved_with_a_home_url() {
        let (mut strip, ids) = strip_with(3);
        let folder = strip.create_group("Reading", AccentColor::Ocean, &[ids[0]]);
        assert!(strip.is_saved(ids[0]));
        assert!(!strip.is_saved(ids[1]));
        assert_eq!(
            strip.tab(ids[0]).and_then(|t| t.home_url.as_deref()),
            Some("https://site0.test")
        );

        // Dragging a tab into the folder saves it too.
        assert!(strip.move_tab(ids[1], Placement::InGroup(folder, None)));
        assert!(strip.is_saved(ids[1]));
        assert!(strip.tab(ids[1]).is_some_and(|t| t.home_url.is_some()));

        // Taking it out of the folder forgets its home.
        assert!(strip.move_tab(ids[1], Placement::SectionEnd(Section::Unpinned)));
        assert!(!strip.is_saved(ids[1]));
        assert!(strip.tab(ids[1]).is_some_and(|t| t.home_url.is_none()));
    }

    #[test]
    fn an_empty_folder_stays_until_deleted() {
        let (mut strip, ids) = strip_with(1);
        let folder = strip.create_group("Empty", AccentColor::Ocean, &[]);
        assert!(strip.group(folder).is_some_and(|g| g.tabs.is_empty()));

        strip.move_tab(ids[0], Placement::InGroup(folder, None));
        strip.remove(ids[0]);
        assert!(
            strip.group(folder).is_some(),
            "closing a folder's last tab keeps the folder"
        );
    }

    #[test]
    fn new_tabs_open_outside_folders() {
        let (mut strip, ids) = strip_with(3);
        let folder = strip.create_group("Reading", AccentColor::Ocean, &[ids[0]]);
        strip.pin(ids[2]);

        // From a regular tab: right after it.
        assert_eq!(
            strip.placement_for_new_tab(Some(ids[1])),
            Placement::AfterTab(ids[1])
        );
        // From a tab in a folder: right after the folder, not inside it.
        assert_eq!(
            strip.placement_for_new_tab(Some(ids[0])),
            Placement::AfterGroup(folder)
        );
        let new = strip.insert(
            Tab::new("https://new.test"),
            strip.placement_for_new_tab(Some(ids[0])),
        );
        assert!(!strip.is_saved(new));
        assert_eq!(strip.location_of(new).and_then(|l| l.group), None);
        // From a pinned tab or nothing: top of the regular tabs.
        for anchor in [Some(ids[2]), None] {
            assert_eq!(
                strip.placement_for_new_tab(anchor),
                Placement::SectionStart(Section::Unpinned)
            );
        }
    }

    #[test]
    fn create_split_gathers_tabs_next_to_the_first() {
        let (mut strip, ids) = strip_with(4);
        let split = strip
            .create_split(&[ids[0], ids[3]], SplitOrientation::Horizontal)
            .expect("two tabs");
        assert_eq!(
            strip.ordered_tab_ids(),
            vec![ids[0], ids[3], ids[1], ids[2]]
        );
        assert_eq!(strip.split_of(ids[3]).map(|s| s.id), Some(split));
        // One row for the split, none for its second tab.
        let rows = strip.rows(None);
        assert_eq!(rows.len(), 3);
        assert_eq!(
            rows[0],
            Row::Split {
                id: split,
                section: Section::Unpinned,
                group: None
            }
        );
        assert!(
            strip
                .create_split(&[ids[1]], SplitOrientation::Horizontal)
                .is_none()
        );
        assert!(
            strip
                .create_split(&[ids[1], TabId::new()], SplitOrientation::Horizontal)
                .is_none(),
            "unknown tabs don't count"
        );
    }

    #[test]
    fn a_split_made_in_a_folder_is_saved_in_that_folder() {
        let (mut strip, ids) = strip_with(3);
        let folder = strip.create_group("Research", AccentColor::Ocean, &[ids[0]]);
        strip.create_split(&[ids[0], ids[2]], SplitOrientation::Horizontal);
        assert_eq!(
            strip.group(folder).map(|g| g.tabs.clone()),
            Some(vec![ids[0], ids[2]])
        );
        assert!(
            strip.is_saved(ids[2]),
            "the joined tab is kept like the folder's tabs"
        );

        // Collapsed, the folder still shows the split of the active tab.
        strip.set_group_collapsed(folder, true);
        let rows = strip.rows(Some(ids[2]));
        assert!(
            rows.iter()
                .any(|r| matches!(r, Row::Split { group: Some(g), .. } if *g == folder))
        );
        assert_eq!(strip.rows(None).len(), 2, "folder header and the other tab");
    }

    #[test]
    fn moving_one_pane_moves_the_whole_split() {
        let (mut strip, ids) = strip_with(4);
        strip.create_split(&[ids[1], ids[2]], SplitOrientation::Horizontal);
        assert!(strip.move_tab(ids[2], Placement::SectionStart(Section::Unpinned)));
        assert_eq!(
            strip.ordered_tab_ids(),
            vec![ids[1], ids[2], ids[0], ids[3]]
        );

        // Into a folder, together.
        let folder = strip.create_group("F", AccentColor::Rose, &[ids[3]]);
        assert!(strip.move_tab(ids[1], Placement::InGroup(folder, Some(0))));
        assert_eq!(
            strip.group(folder).map(|g| g.tabs.clone()),
            Some(vec![ids[1], ids[2], ids[3]])
        );
        // Pinning one pane pins the split.
        assert!(strip.pin(ids[2]));
        assert!(strip.is_pinned(ids[1]) && strip.is_pinned(ids[2]));
        // Moving relative to its own pane does nothing.
        assert!(!strip.move_tab(ids[1], Placement::AfterTab(ids[2])));
    }

    #[test]
    fn tabs_never_land_inside_a_split() {
        let (mut strip, ids) = strip_with(3);
        strip.create_split(&[ids[0], ids[1]], SplitOrientation::Horizontal);
        let between = strip.insert(Tab::default(), Placement::AfterTab(ids[0]));
        assert_eq!(
            strip.ordered_tab_ids(),
            vec![ids[0], ids[1], between, ids[2]]
        );
        // New tabs opened from a pane go after the split.
        assert_eq!(
            strip.placement_for_new_tab(Some(ids[0])),
            Placement::AfterTab(ids[1])
        );
        // A folder dropped onto the second pane lands after the split.
        let folder = strip.create_group("F", AccentColor::Sage, &[ids[2]]);
        strip.move_group(folder, GroupPlacement::BeforeItem(Item::Tab(ids[1])));
        let order = strip.ordered_tab_ids();
        assert_eq!(&order[..2], &[ids[0], ids[1]]);
    }

    #[test]
    fn closing_a_pane_dissolves_a_split_of_two() {
        let (mut strip, ids) = strip_with(3);
        let split = strip
            .create_split(&[ids[0], ids[1], ids[2]], SplitOrientation::Horizontal)
            .expect("split");
        strip.remove(ids[1]);
        assert_eq!(
            strip.split(split).map(|s| s.tabs.clone()),
            Some(vec![ids[0], ids[2]])
        );
        strip.remove(ids[2]);
        assert!(strip.split(split).is_none());
        assert!(strip.split_of(ids[0]).is_none());
    }

    #[test]
    fn remove_from_split_puts_the_tab_after_it() {
        let (mut strip, ids) = strip_with(4);
        let split = strip
            .create_split(&[ids[0], ids[1], ids[2]], SplitOrientation::Horizontal)
            .expect("split");
        assert!(strip.remove_from_split(ids[0]));
        assert_eq!(
            strip.split(split).map(|s| s.tabs.clone()),
            Some(vec![ids[1], ids[2]])
        );
        assert_eq!(
            strip.ordered_tab_ids(),
            vec![ids[1], ids[2], ids[0], ids[3]]
        );
        assert!(strip.remove_from_split(ids[2]));
        assert!(strip.split(split).is_none(), "one tab left is no split");
        assert!(!strip.remove_from_split(ids[3]));
    }

    #[test]
    fn a_tab_joins_only_one_split() {
        let (mut strip, ids) = strip_with(4);
        let first = strip
            .create_split(&[ids[0], ids[1]], SplitOrientation::Horizontal)
            .expect("split");
        let second = strip
            .create_split(&[ids[1], ids[2]], SplitOrientation::Vertical)
            .expect("split");
        assert!(
            strip.split(first).is_none(),
            "the first split lost a pane and dissolved"
        );
        assert!(strip.add_to_split(second, ids[3], 1));
        assert_eq!(
            strip.split(second).map(|s| s.tabs.clone()),
            Some(vec![ids[1], ids[3], ids[2]])
        );
        assert_eq!(&strip.ordered_tab_ids()[1..4], &[ids[1], ids[3], ids[2]]);
        assert!(!strip.add_to_split(second, ids[3], 9), "already a pane");
    }

    #[test]
    fn split_resize_flip_and_dissolve() {
        let (mut strip, ids) = strip_with(2);
        let split = strip
            .create_split(&ids, SplitOrientation::Horizontal)
            .expect("split");
        assert!(strip.resize_split(split, 0, 0.1));
        assert!(strip.flip_split(split));
        assert_eq!(
            strip.split(split).map(|s| s.orientation),
            Some(SplitOrientation::Vertical)
        );
        assert!(strip.equalize_split(split));
        assert_eq!(
            strip.split(split).map(|s| s.sizes.clone()),
            Some(vec![0.5, 0.5])
        );
        assert!(strip.dissolve_split(split));
        assert_eq!(strip.ordered_tab_ids(), ids, "tabs stay where they were");
    }

    #[test]
    fn splits_move_with_their_folder() {
        let (mut strip, ids) = strip_with(3);
        let folder = strip.create_group("F", AccentColor::Amber, &[ids[0], ids[1]]);
        strip.create_split(&[ids[0], ids[1]], SplitOrientation::Horizontal);
        let taken = strip.take_group(folder).expect("folder");
        assert_eq!(taken.splits.len(), 1);
        assert_eq!(strip.splits().count(), 0);
        let mut other = TabStrip::new();
        other.insert_group(taken);
        assert!(other.split_of(ids[1]).is_some());
    }

    #[test]
    fn from_parts_repairs_splits() {
        let tabs: Vec<Tab> = (0..3)
            .map(|i| Tab::new(format!("https://{i}.test")))
            .collect();
        let ids: Vec<TabId> = tabs.iter().map(|t| t.id).collect();
        let good = TabSplit::new(&[ids[0], ids[2]], SplitOrientation::Horizontal);
        let dangling = TabSplit::new(&[ids[1], TabId::new()], SplitOrientation::Horizontal);
        let strip = TabStrip::from_parts(
            tabs,
            vec![],
            vec![],
            ids.iter().copied().map(Item::Tab).collect(),
            vec![good.clone(), dangling],
        );
        assert_eq!(strip.splits().count(), 1);
        assert_eq!(strip.ordered_tab_ids(), vec![ids[0], ids[2], ids[1]]);
        let json = serde_json::to_string(&strip).expect("serialize");
        let back: TabStrip = serde_json::from_str(&json).expect("deserialize");
        assert_eq!(
            back.split(good.id).map(|s| s.tabs.clone()),
            Some(vec![ids[0], ids[2]])
        );
    }
}

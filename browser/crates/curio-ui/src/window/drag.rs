//! Drag-and-drop payloads for tabs and groups, with their drag previews.

use curio_core::{GroupId, SpaceId, TabId};
use gpui_kit::assets::IconName;
use gpui_kit::component::{Icon, Sizable as _};
use gpui_kit::{Context, IntoElement, Render, SharedString, Styled as _, Window, px};

use crate::components::{DragPreview, Favicon};

/// A tab being dragged.
#[derive(Debug, Clone)]
pub(crate) struct DraggedTab {
    pub id: TabId,
    pub title: SharedString,
    pub favicon: Option<String>,
}

impl Render for DraggedTab {
    fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl IntoElement {
        DragPreview::new(
            Favicon::new(self.title.clone()).url(self.favicon.as_deref()),
            self.title.clone(),
        )
    }
}

/// A group being dragged.
#[derive(Debug, Clone)]
pub(crate) struct DraggedGroup {
    pub id: GroupId,
    pub space: SpaceId,
    pub name: SharedString,
}

impl Render for DraggedGroup {
    fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl IntoElement {
        DragPreview::new(Icon::new(IconName::Folder).small(), self.name.clone()).w(px(200.))
    }
}

//! Drag-and-drop payloads for tabs and groups, with their drag previews.

use curio_core::{GroupId, SpaceId, TabId};
use gpui_kit::assets::IconName;
use gpui_kit::component::{Icon, Sizable as _, h_flex};
use gpui_kit::{
    Context, IntoElement, ParentElement as _, Render, SharedString, Styled as _, Window, div, px,
};

use crate::components::favicon;
use crate::theme::CurioTheme;

/// A tab being dragged.
#[derive(Debug, Clone)]
pub(crate) struct DraggedTab {
    pub id: TabId,
    pub title: SharedString,
    pub favicon: Option<String>,
}

impl Render for DraggedTab {
    fn render(&mut self, _: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let theme = *CurioTheme::get(cx);
        h_flex()
            .gap(px(8.))
            .h(px(32.))
            .px(px(10.))
            .w(px(220.))
            .rounded(px(8.))
            .bg(theme.surface_raised)
            .border_1()
            .border_color(theme.surface_border)
            .shadow_lg()
            .text_sm()
            .text_color(theme.text)
            .child(favicon(self.favicon.as_deref(), &self.title, px(16.)))
            .child(div().flex_1().truncate().child(self.title.clone()))
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
    fn render(&mut self, _: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let theme = *CurioTheme::get(cx);
        h_flex()
            .gap(px(8.))
            .h(px(32.))
            .px(px(10.))
            .w(px(200.))
            .rounded(px(8.))
            .bg(theme.surface_raised)
            .border_1()
            .border_color(theme.surface_border)
            .shadow_lg()
            .text_sm()
            .text_color(theme.text)
            .child(Icon::new(IconName::Folder).small())
            .child(div().flex_1().truncate().child(self.name.clone()))
    }
}

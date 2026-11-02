//! An indeterminate progress line.

use std::time::Duration;

use gpui_kit::component::StyledExt as _;
use gpui_kit::{
    Animation, AnimationExt as _, App, ElementId, IntoElement, ParentElement as _, RenderOnce,
    StyleRefinement, Styled, Window, div, px, relative,
};

use crate::theme::CurioTheme;

/// A thin accent bar sweeping across its track while something loads.
///
/// The track fills its parent's width; position it with `.absolute()` and
/// friends.
#[derive(IntoElement)]
pub struct LoadingBar {
    id: ElementId,
    style: StyleRefinement,
    period: Duration,
    fraction: f32,
}

impl LoadingBar {
    /// A bar a third of the track wide, crossing it every 1.2s.
    #[must_use]
    pub fn new(id: impl Into<ElementId>) -> Self {
        Self {
            id: id.into(),
            style: StyleRefinement::default(),
            period: Duration::from_millis(1200),
            fraction: 0.3,
        }
    }

    /// How long one sweep takes.
    #[must_use]
    pub fn period(mut self, period: Duration) -> Self {
        self.period = period;
        self
    }

    /// The bar's width as a fraction of the track, from 0 to 1.
    #[must_use]
    pub fn fraction(mut self, fraction: f32) -> Self {
        self.fraction = fraction.clamp(0.05, 1.0);
        self
    }
}

impl Styled for LoadingBar {
    fn style(&mut self) -> &mut StyleRefinement {
        &mut self.style
    }
}

impl RenderOnce for LoadingBar {
    fn render(self, _: &mut Window, cx: &mut App) -> impl IntoElement {
        let accent = CurioTheme::get(cx).accent;
        let fraction = self.fraction;
        div()
            .w_full()
            .h(px(2.))
            .overflow_hidden()
            .child(
                div()
                    .h_full()
                    .w(relative(fraction))
                    .rounded_full()
                    .bg(accent)
                    .with_animation(
                        self.id,
                        Animation::new(self.period)
                            .repeat()
                            .with_easing(gpui_kit::ease_in_out),
                        move |el, t| el.ml(relative(-fraction + (1. + fraction) * t)),
                    ),
            )
            .refine_style(&self.style)
    }
}

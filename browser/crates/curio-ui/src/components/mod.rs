//! Curio's reusable UI components.
//!
//! Every view builds on these pieces instead of styling raw `div`s, so the
//! chrome stays consistent and a look can be changed in one place.
//!
//! # Conventions
//!
//! - Components are builder structs that render with [`gpui_kit::RenderOnce`].
//!   Construct with `new`, configure with chained methods, and pass them to
//!   `.child(...)` like any element.
//! - Colors come from the global [`CurioTheme`](crate::theme::CurioTheme), so
//!   components follow the active space's accent and light/dark mode.
//! - Most components implement [`Styled`](gpui_kit::Styled). Styles you set
//!   are applied *after* the component's defaults, so `.h(px(44.))` or
//!   `.rounded(px(10.))` tweak one instance without forking the component.
//! - Interactive components implement `InteractiveElement` and
//!   `StatefulInteractiveElement`, so `on_click`, `tooltip`, `on_drag`,
//!   `drag_over`, `on_drop` and `context_menu` work as on a `div`. Hover
//!   styling is owned by the component (GPUI allows one hover style per
//!   element), so use the component's own options instead of `.hover(...)`.
//!
//! # Example
//!
//! ```ignore
//! use crate::components::prelude::*;
//!
//! IconButton::new("back", IconName::ArrowLeft)
//!     .tooltip("Back")
//!     .action(actions::GoBack)
//!     .disabled(!can_go_back);
//! ```

mod chip;
mod color_dot;
mod divider;
mod drag_preview;
mod empty_state;
mod favicon;
mod icon_button;
mod icon_tile;
mod kbd;
mod list_item;
mod loading_bar;
mod menu;
mod rail_item;
mod search_field;
mod section_label;
mod setting_row;
mod style;

pub use chip::Chip;
pub use color_dot::ColorDot;
pub use divider::Divider;
pub use drag_preview::DragPreview;
pub use empty_state::EmptyState;
pub use favicon::{Favicon, logo_mark};
pub use icon_button::IconButton;
pub use icon_tile::IconTile;
pub use kbd::Kbd;
pub use list_item::{ListItem, SelectedStyle};
pub use loading_bar::LoadingBar;
pub use menu::entity_item;
pub use rail_item::RailItem;
pub use search_field::SearchField;
pub use section_label::SectionLabel;
pub use setting_row::SettingRow;
pub use style::{CurioStyled, TooltipExt, WindowDragExt, dialog_footer, traffic_lights_spacer};

/// Everything needed to build UI with Curio's components in one import.
pub mod prelude {
    pub use super::{
        Chip, ColorDot, CurioStyled as _, Divider, DragPreview, EmptyState, Favicon, IconButton,
        IconTile, Kbd, ListItem, LoadingBar, RailItem, SearchField, SectionLabel, SelectedStyle,
        SettingRow, TooltipExt as _, WindowDragExt as _, dialog_footer, entity_item, logo_mark,
        traffic_lights_spacer,
    };
}

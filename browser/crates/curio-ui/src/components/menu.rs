//! Helpers for building popup and context menus.

use gpui_kit::component::menu::PopupMenuItem;
use gpui_kit::{Context, SharedString, WeakEntity, Window};

/// A menu item that runs `action` on the view behind `entity`.
///
/// Saves cloning the weak handle and unwrapping the update for every item.
/// Chain `.icon(...)` or `.checked(...)` on the result as usual:
///
/// ```ignore
/// menu.item(
///     entity_item(&this, "Close Tab", move |this, window, cx| this.close_tab(id, window, cx))
///         .icon(IconName::X),
/// )
/// ```
///
/// Nothing happens if the view has been released.
pub fn entity_item<T: 'static>(
    entity: &WeakEntity<T>,
    label: impl Into<SharedString>,
    action: impl Fn(&mut T, &mut Window, &mut Context<T>) + 'static,
) -> PopupMenuItem {
    let entity = entity.clone();
    PopupMenuItem::new(label).on_click(move |_, window, cx| {
        // A released view simply ignores the click.
        let _ = entity.update(cx, |this, cx| action(this, window, cx));
    })
}

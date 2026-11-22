mod tools;

use tauri::image::Image;
use tauri::menu::{CheckMenuItem, Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Emitter, Manager, Wry};
use tauri_plugin_window_state::StateFlags;

struct PinItem(CheckMenuItem<Wry>);

fn show_deck(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("deck") {
        let _ = window.unminimize();
        let _ = window.show();
        let _ = window.set_focus();
    }
}

fn toggle_deck(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("deck") {
        let visible = window.is_visible().unwrap_or(false) && !window.is_minimized().unwrap_or(false);
        if visible { let _ = window.hide(); } else { show_deck(app); }
    }
}

/// The Deck owns the pin setting; the tray mirrors it.
#[tauri::command]
fn sync_pinned(app: AppHandle, pinned: bool) {
    if let Some(item) = app.try_state::<PinItem>() {
        let _ = item.0.set_checked(pinned);
    }
}

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| show_deck(app)))
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_window_state::Builder::new().with_state_flags(StateFlags::POSITION).build())
        .invoke_handler(tauri::generate_handler![
            sync_pinned,
            tools::platform_info,
            tools::find_tool,
            tools::run_tool,
            tools::prepare_profile,
            tools::install_codexbar,
            tools::state_path,
            tools::load_state,
            tools::save_state,
        ])
        .setup(|app| {
            let toggle = MenuItem::with_id(app, "toggle", "Show or Hide Deck", true, None::<&str>)?;
            let pin = CheckMenuItem::with_id(app, "pin", "Pin Above Other Windows", true, true, None::<&str>)?;
            let refresh = MenuItem::with_id(app, "refresh", "Refresh Usage", true, None::<&str>)?;
            let quit = MenuItem::with_id(app, "quit", "Quit Token Burn", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&toggle, &pin, &refresh, &PredefinedMenuItem::separator(app)?, &quit])?;
            app.manage(PinItem(pin));
            TrayIconBuilder::with_id("deck")
                .icon(Image::from_bytes(include_bytes!("../icons/tray.png"))?)
                .tooltip("Token Burn — Deck")
                .menu(&menu)
                .show_menu_on_left_click(false)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "toggle" => toggle_deck(app),
                    "pin" => { let _ = app.emit("tray-toggle-pin", ()); }
                    "refresh" => {
                        show_deck(app);
                        let _ = app.emit("tray-refresh", ());
                    }
                    "quit" => app.exit(0),
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::Click { button: MouseButton::Left, button_state: MouseButtonState::Up, .. } = event {
                        toggle_deck(tray.app_handle());
                    }
                })
                .build(app)?;
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running Token Burn");
}

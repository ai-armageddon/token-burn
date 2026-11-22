//! Finds and runs the CodexBar and Claude Code CLIs.
//!
//! Linux (and macOS, for development) run them directly. Windows has no native
//! CodexBar CLI, so both tools run inside the default WSL distribution, and the
//! per-login Claude profiles live in the WSL home directory.

use serde::Serialize;
use std::collections::HashMap;
use std::io::Read;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::mpsc;
use std::time::{Duration, Instant};
use tauri::{AppHandle, Manager};

/// The only programs the Deck may start.
const TOOLS: [&str; 2] = ["codexbar", "claude"];
/// The only variables the Deck may pass to them.
const ENV_KEYS: [&str; 2] = ["CLAUDE_CONFIG_DIR", "CODEXBAR_CONFIG"];
/// An isolated Claude profile must not pick up the user's global credentials.
const CLAUDE_TOKENS: [&str; 3] = ["CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN"];
const PROFILE_SOURCE: &str =
    r#"{"version":1,"providers":[{"id":"claude","enabled":true,"source":"cli","cookieSource":"off"}]}"#;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RunOutput {
    code: Option<i32>,
    stdout: String,
    timed_out: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PlatformInfo {
    os: &'static str,
    /// "native" or "wsl".
    runtime: &'static str,
    /// False only on Windows without WSL.
    runtime_available: bool,
    /// Homebrew can install CodexBar here.
    can_install: bool,
}

fn check_tool(name: &str) -> Result<(), String> {
    if TOOLS.contains(&name) { Ok(()) } else { Err(format!("Unknown tool {name}.")) }
}

fn check_env(env: &HashMap<String, String>) -> Result<(), String> {
    match env.keys().find(|k| !ENV_KEYS.contains(&k.as_str())) {
        Some(key) => Err(format!("Unsupported variable {key}.")),
        None => Ok(()),
    }
}

/// Account IDs are UUIDs; anything else could escape the profile folder.
fn check_profile_id(id: &str) -> Result<(), String> {
    let ok = id.len() == 36 && id.chars().all(|c| c.is_ascii_hexdigit() || c == '-');
    if ok { Ok(()) } else { Err("Invalid account ID.".into()) }
}

#[cfg(not(windows))]
mod platform {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    pub const RUNTIME: &str = "native";

    fn home() -> PathBuf {
        std::env::var_os("HOME").map(PathBuf::from).unwrap_or_default()
    }

    pub fn bins() -> Vec<PathBuf> {
        let home = home();
        let mut list: Vec<PathBuf> = vec![
            home.join(".local/bin"),
            "/home/linuxbrew/.linuxbrew/bin".into(),
            home.join(".linuxbrew/bin"),
            "/opt/homebrew/bin".into(),
            "/usr/local/bin".into(),
            home.join(".grok/bin"),
            home.join(".opencode/bin"),
            home.join(".npm-global/bin"),
        ];
        // Desktop launchers often start apps with a minimal PATH, so the
        // install locations above come first and the inherited PATH follows.
        if let Some(path) = std::env::var_os("PATH") {
            list.extend(std::env::split_paths(&path).filter(|p| p.is_absolute()));
        }
        let mut seen = std::collections::HashSet::new();
        list.retain(|p| seen.insert(p.clone()));
        list
    }

    fn executable(path: &PathBuf) -> bool {
        std::fs::metadata(path).map(|m| m.is_file() && m.permissions().mode() & 0o111 != 0).unwrap_or(false)
    }

    pub fn find(name: &str) -> Option<String> {
        let mut candidates: Vec<PathBuf> = bins().into_iter().map(|b| b.join(name)).collect();
        if cfg!(target_os = "macos") && name == "codexbar" {
            for apps in [PathBuf::from("/Applications"), home().join("Applications")] {
                candidates.push(apps.join("CodexBar.app/Contents/Helpers/CodexBarCLI"));
            }
        }
        candidates.into_iter().find(executable).map(|p| p.to_string_lossy().into_owned())
    }

    pub fn available() -> bool {
        true
    }

    pub fn command(path: &str, args: &[String], env: &HashMap<String, String>) -> Command {
        let mut command = Command::new(path);
        command.args(args).envs(env);
        if let Ok(joined) = std::env::join_paths(bins()) {
            command.env("PATH", joined);
        }
        if env.contains_key("CLAUDE_CONFIG_DIR") {
            for key in CLAUDE_TOKENS {
                command.env_remove(key);
            }
        }
        command
    }

    fn private_dir(dir: &PathBuf) -> Result<(), String> {
        std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
        std::fs::set_permissions(dir, std::fs::Permissions::from_mode(0o700)).map_err(|e| e.to_string())
    }

    pub fn prepare_profile(app: &AppHandle, id: &str) -> Result<String, String> {
        let base = app.path().app_data_dir().map_err(|e| e.to_string())?;
        private_dir(&base)?;
        let dir = base.join("claude-profiles").join(id);
        private_dir(&dir)?;
        let config = dir.join("usage-source.json");
        if std::fs::read_to_string(&config).ok().as_deref() != Some(PROFILE_SOURCE) {
            write_atomic(&config, PROFILE_SOURCE)?;
        }
        Ok(dir.to_string_lossy().into_owned())
    }

    pub fn secure_data_dir(dir: &PathBuf) -> Result<(), String> {
        private_dir(dir)
    }

    pub fn install_command() -> Option<Command> {
        let brew = find("brew")?;
        let mut command = Command::new(brew);
        if cfg!(target_os = "macos") {
            command.args(["install", "--cask", "codexbar"]);
        } else {
            command.args(["install", "steipete/tap/codexbar"]);
        }
        if let Ok(joined) = std::env::join_paths(bins()) {
            command.env("PATH", joined);
        }
        command
            .env("HOMEBREW_NO_INSTALL_CLEANUP", "1")
            .env("HOMEBREW_NO_AUTOREMOVE", "1")
            .env("NONINTERACTIVE", "1");
        Some(command)
    }
}

#[cfg(windows)]
mod platform {
    use super::*;
    use std::os::windows::process::CommandExt;

    pub const RUNTIME: &str = "wsl";
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;
    const WSL_BINS: &str =
        r#""$HOME/.local/bin" /home/linuxbrew/.linuxbrew/bin "$HOME/.linuxbrew/bin" /usr/local/bin "$HOME/.grok/bin" "$HOME/.opencode/bin""#;

    fn wsl_path() -> PathBuf {
        let root = std::env::var_os("SystemRoot").map(PathBuf::from).unwrap_or_else(|| "C:\\Windows".into());
        root.join("System32").join("wsl.exe")
    }

    fn wsl() -> Command {
        let mut command = Command::new(wsl_path());
        command.creation_flags(CREATE_NO_WINDOW);
        command
    }

    pub fn available() -> bool {
        wsl_path().is_file()
    }

    pub fn find(name: &str) -> Option<String> {
        if !available() {
            return None;
        }
        let script = format!(
            r#"for d in {WSL_BINS}; do if [ -f "$d/$1" ] && [ -x "$d/$1" ]; then printf '%s' "$d/$1"; exit 0; fi; done; p=$(command -v "$1") && printf '%s' "$p""#
        );
        let output = wsl()
            .args(["-e", "sh", "-lc", &script, "sh", name])
            .stdin(Stdio::null())
            .stderr(Stdio::null())
            .output()
            .ok()?;
        let path = String::from_utf8_lossy(&output.stdout).trim().to_string();
        (output.status.success() && path.starts_with('/')).then_some(path)
    }

    pub fn command(path: &str, args: &[String], env: &HashMap<String, String>) -> Command {
        let script = format!(
            r#"for d in {WSL_BINS}; do PATH="$d:$PATH"; done; export PATH; exec env "$@""#
        );
        let mut command = wsl();
        command.args(["-e", "sh", "-lc", &script, "sh"]);
        if env.contains_key("CLAUDE_CONFIG_DIR") {
            for key in CLAUDE_TOKENS {
                command.args(["-u", key]);
            }
        }
        for (key, value) in env {
            command.arg(format!("{key}={value}"));
        }
        command.arg(path).args(args);
        command
    }

    pub fn prepare_profile(_app: &AppHandle, id: &str) -> Result<String, String> {
        let script = r#"umask 077; d="${XDG_DATA_HOME:-$HOME/.local/share}/token-burn/claude-profiles/$1"; mkdir -p "$d" && printf '%s' "$2" > "$d/usage-source.json" && printf '%s' "$d""#;
        let output = wsl()
            .args(["-e", "sh", "-c", script, "sh", id, PROFILE_SOURCE])
            .stdin(Stdio::null())
            .stderr(Stdio::null())
            .output()
            .map_err(|_| "Install WSL to use Claude logins on Windows.".to_string())?;
        let dir = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if output.status.success() && dir.starts_with('/') {
            Ok(dir)
        } else {
            Err("Could not create the Claude profile folder in WSL.".into())
        }
    }

    pub fn secure_data_dir(dir: &PathBuf) -> Result<(), String> {
        // %APPDATA% is already private to the Windows user.
        std::fs::create_dir_all(dir).map_err(|e| e.to_string())
    }

    pub fn install_command() -> Option<Command> {
        None
    }
}

fn write_atomic(path: &PathBuf, contents: &str) -> Result<(), String> {
    let temp = path.with_extension("json.tmp");
    std::fs::write(&temp, contents).map_err(|e| e.to_string())?;
    std::fs::rename(&temp, path).map_err(|e| e.to_string())
}

/// Runs a child with a bounded wait. A provider can hang on an expired login.
fn run_bounded(mut command: Command, timeout: Duration) -> Result<RunOutput, String> {
    command.stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::null());
    let mut child: Child = command.spawn().map_err(|e| format!("Could not start the CLI: {e}"))?;
    let mut stdout = child.stdout.take().ok_or("The CLI produced no output stream.")?;
    let (sender, receiver) = mpsc::channel();
    std::thread::spawn(move || {
        let mut buffer = Vec::new();
        let _ = stdout.read_to_end(&mut buffer);
        let _ = sender.send(buffer);
    });
    let deadline = Instant::now() + timeout;
    let mut timed_out = false;
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break Some(status),
            Ok(None) if Instant::now() >= deadline => {
                timed_out = true;
                let _ = child.kill();
                break child.wait().ok();
            }
            Ok(None) => std::thread::sleep(Duration::from_millis(100)),
            Err(e) => return Err(e.to_string()),
        }
    };
    // A grandchild can keep the pipe open after the CLI exits; don't wait on it forever.
    let bytes = receiver.recv_timeout(Duration::from_secs(5)).unwrap_or_default();
    Ok(RunOutput {
        code: status.and_then(|s| s.code()),
        stdout: String::from_utf8_lossy(&bytes).into_owned(),
        timed_out,
    })
}

async fn blocking<T: Send + 'static>(work: impl FnOnce() -> Result<T, String> + Send + 'static) -> Result<T, String> {
    tauri::async_runtime::spawn_blocking(work).await.map_err(|e| e.to_string())?
}

#[tauri::command]
pub fn platform_info() -> PlatformInfo {
    PlatformInfo {
        os: std::env::consts::OS,
        runtime: platform::RUNTIME,
        runtime_available: platform::available(),
        can_install: platform::install_command().is_some(),
    }
}

#[tauri::command]
pub async fn find_tool(name: String) -> Result<Option<String>, String> {
    check_tool(&name)?;
    blocking(move || Ok(platform::find(&name))).await
}

#[tauri::command]
pub async fn run_tool(
    name: String,
    args: Vec<String>,
    env: HashMap<String, String>,
    timeout_secs: u64,
) -> Result<RunOutput, String> {
    check_tool(&name)?;
    check_env(&env)?;
    blocking(move || {
        let path = platform::find(&name).ok_or_else(|| format!("Install the {name} CLI to connect this account."))?;
        run_bounded(platform::command(&path, &args, &env), Duration::from_secs(timeout_secs.clamp(1, 600)))
    })
    .await
}

#[tauri::command]
pub async fn prepare_profile(app: AppHandle, id: String) -> Result<HashMap<String, String>, String> {
    check_profile_id(&id)?;
    blocking(move || {
        let dir = platform::prepare_profile(&app, &id)?;
        let config = format!("{dir}/usage-source.json");
        Ok(HashMap::from([("CLAUDE_CONFIG_DIR".into(), dir), ("CODEXBAR_CONFIG".into(), config)]))
    })
    .await
}

#[tauri::command]
pub async fn install_codexbar() -> Result<(), String> {
    blocking(|| {
        if platform::find("codexbar").is_some() {
            return Ok(());
        }
        let command = platform::install_command().ok_or("Open the official installation page below.")?;
        let result = run_bounded(command, Duration::from_secs(600))?;
        if result.code == Some(0) && platform::find("codexbar").is_some() {
            Ok(())
        } else {
            Err("Homebrew could not finish installing CodexBar. Use the installation page below.".into())
        }
    })
    .await
}

fn state_file(app: &AppHandle) -> Result<PathBuf, String> {
    let dir = app.path().app_data_dir().map_err(|e| e.to_string())?;
    platform::secure_data_dir(&dir)?;
    Ok(dir.join("accounts.json"))
}

#[tauri::command]
pub fn state_path(app: AppHandle) -> Result<String, String> {
    Ok(state_file(&app)?.to_string_lossy().into_owned())
}

#[tauri::command]
pub fn load_state(app: AppHandle) -> Result<Option<String>, String> {
    let file = state_file(&app)?;
    match std::fs::read_to_string(&file) {
        Ok(text) => Ok(Some(text)),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(e.to_string()),
    }
}

#[tauri::command]
pub fn save_state(app: AppHandle, contents: String) -> Result<(), String> {
    write_atomic(&state_file(&app)?, &contents)
}

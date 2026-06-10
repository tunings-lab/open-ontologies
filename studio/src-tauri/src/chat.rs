use std::io::BufRead;
use std::io::Write;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::Mutex;
use tauri::{Emitter, Manager};

pub struct ChatState {
    pub process: Mutex<Option<Child>>,
}

fn resolve_node_binary() -> PathBuf {
    #[cfg(target_os = "windows")]
    {
        let candidates = [
            PathBuf::from(r"C:\Program Files\nodejs\node.exe"),
            PathBuf::from(r"C:\Program Files (x86)\nodejs\node.exe"),
        ];
        if let Some(path) = candidates.into_iter().find(|path| path.exists()) {
            return path;
        }
        PathBuf::from("node")
    }
    #[cfg(not(target_os = "windows"))]
    {
        let candidates = [
            PathBuf::from("/opt/homebrew/bin/node"),
            PathBuf::from("/usr/local/bin/node"),
            PathBuf::from("/usr/bin/node"),
        ];
        if let Some(path) = candidates.into_iter().find(|path| path.exists()) {
            return path;
        }
        PathBuf::from("node")
    }
}

fn augmented_path() -> String {
    let mut parts: Vec<String> = Vec::new();
    #[cfg(target_os = "windows")]
    {
        parts.push(r"C:\Program Files\nodejs".to_string());
        if let Some(home) = std::env::var_os("USERPROFILE") {
            parts.push(format!(r"{}\.\cargo\bin", home.to_string_lossy()));
        }
    }
    #[cfg(not(target_os = "windows"))]
    {
        parts.push("/opt/homebrew/bin".to_string());
        parts.push("/usr/local/bin".to_string());
        parts.push("/usr/bin".to_string());
    }
    if let Ok(existing) = std::env::var("PATH") {
        parts.push(existing);
    }
    let separator = if cfg!(target_os = "windows") { ";" } else { ":" };
    parts.join(separator)
}

pub fn spawn_agent_sidecar(app: &tauri::AppHandle) -> Result<(), String> {
    let sidecar_dir = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("sidecars/agent");
    let node = resolve_node_binary();

    let mut child = Command::new(&node)
        .arg(sidecar_dir.join("dist/index.js"))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .env("PATH", augmented_path())
        .spawn()
        .map_err(|e| format!("Failed to spawn agent sidecar: {e}"))?;

    let stdout = child.stdout.take().ok_or("No stdout")?;
    let app_handle = app.clone();

    std::thread::spawn(move || {
        let reader = std::io::BufReader::new(stdout);
        for line in reader.lines() {
            if let Ok(line) = line {
                let _ = app_handle.emit("agent-message", line);
            }
        }
    });

    let stderr = child.stderr.take().ok_or("No stderr")?;
    std::thread::spawn(move || {
        let reader = std::io::BufReader::new(stderr);
        for line in reader.lines() {
            if let Ok(line) = line {
                eprintln!("[agent stderr] {}", line);
            }
        }
    });

    let state = app.state::<ChatState>();
    *state.process.lock().map_err(|e| format!("Lock error: {e}"))? = Some(child);

    Ok(())
}

#[tauri::command]
pub fn send_chat_message(
    message: String,
    mode: String,
    state: tauri::State<ChatState>,
) -> Result<(), String> {
    let mut guard = state.process.lock().map_err(|e| format!("Lock error: {e}"))?;
    let child = guard.as_mut().ok_or("Agent sidecar not running")?;
    let stdin = child.stdin.as_mut().ok_or("No stdin")?;

    let payload = serde_json::json!({ "type": "chat", "message": message, "mode": mode });
    writeln!(stdin, "{}", payload).map_err(|e| format!("Write failed: {e}"))?;
    stdin.flush().map_err(|e| format!("Flush failed: {e}"))?;

    Ok(())
}

#[tauri::command]
pub fn reset_chat(state: tauri::State<ChatState>) -> Result<(), String> {
    let mut guard = state.process.lock().map_err(|e| format!("Lock error: {e}"))?;
    let child = guard.as_mut().ok_or("Agent sidecar not running")?;
    let stdin = child.stdin.as_mut().ok_or("No stdin")?;

    let payload = serde_json::json!({ "type": "reset" });
    writeln!(stdin, "{}", payload).map_err(|e| format!("Write failed: {e}"))?;
    stdin.flush().map_err(|e| format!("Flush failed: {e}"))?;

    Ok(())
}

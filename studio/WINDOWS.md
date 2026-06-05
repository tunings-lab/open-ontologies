# Windows Notes

See the full Windows build guide in [`../docs/windows.md`](../docs/windows.md).

- Local `tauri dev` looks for the engine in `..\target\debug\open-ontologies.exe` or `..\target\release\open-ontologies.exe`, so a macOS-specific sidecar setup is not required on Windows.
- The Tauri backend does not shell out through `sh`, `lsof`, or Homebrew-specific paths when running on Windows.
- Packaged builds use `npm run prepare-engine` to copy `open-ontologies.exe` into `src-tauri/binaries/open-ontologies-x86_64-pc-windows-msvc.exe`.

import fs from "node:fs";
import path from "node:path";

const studioRoot = path.resolve(import.meta.dirname, "..");
const workspaceRoot = path.resolve(studioRoot, "..");
const ext = process.platform === "win32" ? ".exe" : "";

const targetTripleByPlatform = {
  win32: "x86_64-pc-windows-msvc",
  darwin: process.arch === "arm64" ? "aarch64-apple-darwin" : "x86_64-apple-darwin",
  linux: "x86_64-unknown-linux-gnu",
};

const targetTriple = targetTripleByPlatform[process.platform];
if (!targetTriple) {
  console.warn(`Skipping engine bundle prep: unsupported platform ${process.platform}`);
  process.exit(0);
}

const source = path.join(workspaceRoot, "target", "release", `open-ontologies${ext}`);
const binariesDir = path.join(studioRoot, "src-tauri", "binaries");
const destination = path.join(binariesDir, `open-ontologies-${targetTriple}${ext}`);

if (!fs.existsSync(source)) {
  console.warn(
    `Skipping engine bundle prep: ${source} does not exist. Build the engine first with cargo build --release.`,
  );
  process.exit(0);
}

fs.mkdirSync(binariesDir, { recursive: true });
fs.copyFileSync(source, destination);
console.log(`Prepared bundled engine binary: ${destination}`);

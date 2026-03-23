// hook.mjs
import { readFileSync, writeFileSync, readdirSync, openSync, closeSync, mkdirSync, existsSync, unlinkSync } from "node:fs";
import { join, dirname, resolve } from "node:path";
import { spawn, execSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { homedir } from "node:os";
var hookDir = dirname(fileURLToPath(import.meta.url));
function findGdlRoot(cwd) {
  let dir = resolve(cwd);
  let check = dir;
  while (check !== dirname(check)) {
    if (existsSync(join(check, ".claude", "greppable.local.md"))) {
      return check;
    }
    check = dirname(check);
  }
  try {
    const gitRoot = execSync("git rev-parse --show-toplevel", { cwd: dir, encoding: "utf8" }).trim();
    if (gitRoot) return gitRoot;
  } catch {
  }
  return dir;
}
function parseConfig(filePath) {
  if (!existsSync(filePath)) return {};
  let content;
  try {
    content = readFileSync(filePath, "utf-8");
  } catch {
    return {};
  }
  const fenceMatch = content.match(/^---\n([\s\S]*?)\n---/);
  if (!fenceMatch) return {};
  const config = {};
  for (const line of fenceMatch[1].split("\n")) {
    const m = line.match(/^\s*(\w+)\s*:\s*(.+)$/);
    if (!m) continue;
    let val = m[2].trim();
    val = val.replace(/^["'](.*)["']$/, "$1");
    config[m[1]] = val;
  }
  return config;
}
function readConfigCascade(cwd) {
  const globalPath = join(homedir(), ".claude", "greppable.local.md");
  const projectPath = join(cwd, ".claude", "greppable.local.md");
  const globalConfig = parseConfig(globalPath);
  const projectConfig = parseConfig(projectPath);
  const merged = { ...globalConfig };
  for (const [key, val] of Object.entries(projectConfig)) {
    if (val !== void 0 && val !== "") merged[key] = val;
  }
  return merged;
}
function resolveSessionDir(cwd) {
  const projectsDir = join(homedir(), ".claude", "projects");
  if (!existsSync(projectsDir)) return null;
  const encoded = cwd.replace(/[\\/:.]/g, "-");
  const exact = join(projectsDir, encoded);
  if (existsSync(exact)) return exact;
  const legacy = cwd.replace(/[\\/:]/g, "-");
  const legacyPath = join(projectsDir, legacy);
  if (existsSync(legacyPath)) return legacyPath;
  const cwdParts = cwd.split(/[\\/]/);
  const cwdBase = cwdParts[cwdParts.length - 1];
  if (!cwdBase) return null;
  try {
    const entries = readdirSync(projectsDir, { withFileTypes: true });
    const matches = entries.filter((e) => e.isDirectory() && e.name.endsWith("-" + cwdBase));
    if (matches.length === 1) return join(projectsDir, matches[0].name);
    if (matches.length > 1) {
      console.error(`session dir ambiguous: ${matches.length} dirs match basename "${cwdBase}"`);
      return null;
    }
  } catch {
  }
  return null;
}
function backgroundMode() {
  try {
    const input = readFileSync(0, "utf-8");
    let cwd;
    try {
      cwd = JSON.parse(input).cwd;
    } catch {
      process.exit(0);
    }
    if (!cwd) process.exit(0);
    cwd = findGdlRoot(cwd);
    const logPath = join(cwd, ".claude", "session2gdlm.log");
    mkdirSync(dirname(logPath), { recursive: true });
    const logFd = openSync(logPath, "a");
    const child = spawn(process.execPath, [join(hookDir, "hook.mjs"), "--cwd=" + cwd], {
      detached: true,
      stdio: ["ignore", logFd, logFd]
    });
    child.unref();
    closeSync(logFd);
    process.exit(0);
  } catch {
    process.exit(0);
  }
}
function cwdMode(cwd) {
  cwd = findGdlRoot(cwd);
  const lockPath = join(cwd, ".claude", "session2gdlm.lock");
  mkdirSync(dirname(lockPath), { recursive: true });
  try {
    const existing = JSON.parse(readFileSync(lockPath, "utf-8"));
    const age = Date.now() - (existing.ts || 0);
    let alive = false;
    try {
      process.kill(existing.pid, 0);
      alive = true;
    } catch (e) {
      alive = e.code === "EPERM";
    }
    if (alive && age < 3e5) {
      console.log(`[${(/* @__PURE__ */ new Date()).toISOString()}] session2gdlm skipped \u2014 lock held by PID ${existing.pid}`);
      process.exit(0);
    }
    try {
      unlinkSync(lockPath);
    } catch {
    }
  } catch {
  }
  try {
    writeFileSync(lockPath, JSON.stringify({ pid: process.pid, ts: Date.now() }), { flag: "wx" });
  } catch (err) {
    if (err.code === "EEXIST") {
      console.log(`[${(/* @__PURE__ */ new Date()).toISOString()}] session2gdlm skipped \u2014 lock claimed by another process`);
      process.exit(0);
    }
    process.exit(0);
  }
  console.log(`[${(/* @__PURE__ */ new Date()).toISOString()}] session2gdlm hook started for ${cwd}`);
  const config = readConfigCascade(cwd);
  if (config.memory !== "true") {
    console.log(`memory disabled for ${cwd} (memory=${config.memory || "unset"})`);
    try {
      unlinkSync(lockPath);
    } catch {
    }
    process.exit(0);
  }
  const gdlRoot = config.gdl_root || "docs/gdl";
  const sessionDir = resolveSessionDir(cwd);
  const outputDir = join(cwd, gdlRoot, "memory", "active");
  if (!sessionDir) {
    console.log(`session dir not found for: ${cwd}`);
    try {
      unlinkSync(lockPath);
    } catch {
    }
    process.exit(0);
  }
  mkdirSync(outputDir, { recursive: true });
  const metricsOutput = join(cwd, gdlRoot, "metrics", "sessions.gdl");
  const child = spawn(process.execPath, [
    join(hookDir, "index.mjs"),
    "--dir=" + sessionDir,
    "--output=" + outputDir,
    "--metrics-output=" + metricsOutput,
    "--limit=1"
  ], { detached: true, stdio: "inherit" });
  const timer = setTimeout(() => {
    try {
      process.kill(-child.pid, "SIGTERM");
    } catch {
    }
    try {
      unlinkSync(lockPath);
    } catch {
    }
    setTimeout(() => process.exit(1), 2e3);
  }, 3e5);
  child.on("exit", (code) => {
    clearTimeout(timer);
    try {
      unlinkSync(lockPath);
    } catch {
    }
    console.log(`[${(/* @__PURE__ */ new Date()).toISOString()}] session2gdlm exited with code ${code}`);
    if (code === 0 && config.compaction_auto === "true") {
      const activeDir = join(cwd, gdlRoot, "memory", "active");
      try {
        let count = 0;
        const files = readdirSync(activeDir).filter((f) => f.endsWith(".gdlm"));
        for (const f of files) {
          const content = readFileSync(join(activeDir, f), "utf-8");
          count += (content.match(/^@memory/gm) || []).length;
        }
        if (count > 200) {
          console.log(`[${(/* @__PURE__ */ new Date()).toISOString()}] auto-compaction: ${count} records > 200 threshold`);
          let compactScript = join(hookDir, "..", "gdlm-compact.sh");
          if (!existsSync(compactScript)) compactScript = join(hookDir, "..", "..", "gdlm-compact.sh");
          if (existsSync(compactScript)) {
            const memoryDir = join(cwd, gdlRoot, "memory");
            const compactLogPath = join(cwd, ".claude", "gdlm-compact.log");
            const compactLogFd = openSync(compactLogPath, "a");
            const compactChild = spawn("bash", [compactScript, memoryDir], {
              detached: true,
              stdio: ["ignore", compactLogFd, compactLogFd]
            });
            compactChild.unref();
            closeSync(compactLogFd);
          } else {
            console.log(`[${(/* @__PURE__ */ new Date()).toISOString()}] auto-compaction: gdlm-compact.sh not found, skipping`);
          }
        }
      } catch (err) {
        console.error(`compaction check error: ${err.message}`);
      }
    }
    process.exit(code || 0);
  });
  child.on("error", (err) => {
    clearTimeout(timer);
    try {
      unlinkSync(lockPath);
    } catch {
    }
    console.error(`session2gdlm spawn error: ${err.message}`);
    process.exit(0);
  });
}
var args = process.argv.slice(2);
if (args.includes("--background")) {
  backgroundMode();
} else {
  const cwdArg = args.find((a) => a.startsWith("--cwd="));
  if (cwdArg) {
    cwdMode(cwdArg.slice("--cwd=".length));
  } else {
    console.error("Usage: hook.mjs --background   (reads stdin JSON, spawns detached child)");
    console.error("       hook.mjs --cwd=PATH     (reads config, runs session2gdlm)");
    process.exit(1);
  }
}

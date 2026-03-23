/**
 * src2gdlc — Multi-language source to GDLC v2 file-level index
 *
 * Generic walker + per-language mapping configs.
 * Adding a new language = adding a new mapping file in mappings/.
 */
import { readdirSync, lstatSync, statSync, existsSync, writeFileSync, readFileSync, renameSync, unlinkSync } from 'fs';
import { basename, dirname, join, relative, resolve, extname } from 'path';
import { execSync } from 'child_process';
import { fileURLToPath } from 'url';
import { formatGdlcV2, computeSourceHash } from './shared.js';
import { extractFile } from './extract.js';

// Language mappings — add new languages by importing a new mapping file
import typescriptMapping from './mappings/typescript.js';
import pythonMapping from './mappings/python.js';
import goMapping from './mappings/go.js';
import javaMapping from './mappings/java.js';
import rustMapping from './mappings/rust.js';
import javascriptMapping from './mappings/javascript.js';
import csharpMapping from './mappings/csharp.js';
import cMapping from './mappings/c.js';
import cppMapping from './mappings/cpp.js';
import rubyMapping from './mappings/ruby.js';
import phpMapping from './mappings/php.js';
import kotlinMapping from './mappings/kotlin.js';
import swiftMapping from './mappings/swift.js';
import bashMapping from './mappings/bash.js';

const mappings = [typescriptMapping, pythonMapping, goMapping, javaMapping, rustMapping, javascriptMapping, csharpMapping, cMapping, cppMapping, rubyMapping, phpMapping, kotlinMapping, swiftMapping, bashMapping];

/** Find the mapping for a given file extension */
function mappingForExt(ext) {
  return mappings.find(m => m.extensions.includes(ext));
}

/** Get all supported extensions */
function allExtensions() {
  return mappings.flatMap(m => m.extensions);
}

const EXCLUDE_DIRS = new Set([
  'node_modules', '.git', '__pycache__', '.venv', 'vendor', 'target',
  'dist', 'build', '.next', '.nuxt', '.output', 'out',
]);

/** Read a .gdlignore file and return patterns applicable to a given format */
function readGdlignore(filePath, format) {
  if (!existsSync(filePath)) return [];
  const lines = readFileSync(filePath, 'utf-8').split('\n');
  const patterns = [];
  for (const raw of lines) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    // Check for format prefix (e.g. gdlc:pattern)
    const prefixMatch = line.match(/^(gdl[a-z]*):(.*)/);
    if (prefixMatch) {
      if (prefixMatch[1] === format) {
        const pat = prefixMatch[2].trim();
        if (pat) patterns.push(pat);
      }
    } else {
      patterns.push(line);
    }
  }
  return patterns;
}

/** Convert a glob pattern to a regex string */
function globToRegex(glob) {
  // Replace **, *, ? with sentinels BEFORE escaping regex chars,
  // so glob characters don't get escaped and lost.
  let result = glob.replace(/\*\*/g, '@@DSTAR@@');
  result = result.replace(/\*/g, '@@STAR@@');
  result = result.replace(/\?/g, '@@QMARK@@');
  // Now escape remaining regex metacharacters
  result = result.replace(/[.+^${}()|[\]\\]/g, '\\$&');
  // Replace sentinels with regex equivalents
  result = result.replace(/@@DSTAR@@/g, '.*');
  result = result.replace(/@@STAR@@/g, '[^/]*');
  result = result.replace(/@@QMARK@@/g, '[^/]');
  if (result.startsWith('/')) result = result.slice(1);
  return result;
}

/** Check if a file path should be excluded based on .gdlignore patterns */
function shouldExclude(filePath, patterns) {
  for (const pattern of patterns) {
    if (pattern.endsWith('/')) {
      // Directory pattern
      const dir = pattern.slice(0, -1);
      if (dir.startsWith('/')) {
        // Root-relative
        const rootDir = dir.slice(1);
        if (rootDir.includes('*') || rootDir.includes('?')) {
          // Root-relative with glob — convert to regex
          const regex = globToRegex(rootDir);
          if (new RegExp(`^${regex}/`).test(filePath)) return true;
        } else {
          if (filePath.startsWith(rootDir + '/')) return true;
        }
      } else if (dir.includes('*') || dir.includes('?')) {
        // Glob directory — convert to regex
        const regex = globToRegex(dir);
        if (new RegExp(`(^|/)${regex}/`).test(filePath)) return true;
      } else {
        // Bare directory — match anywhere (segment-boundary)
        if (filePath.startsWith(dir + '/') || filePath.includes('/' + dir + '/')) return true;
      }
    } else if (pattern.includes('*') || pattern.includes('?')) {
      // File glob pattern
      const regex = globToRegex(pattern);
      if (pattern.startsWith('/')) {
        if (new RegExp(`^${regex}$`).test(filePath)) return true;
      } else {
        if (new RegExp(`(^|/)${regex}$`).test(filePath)) return true;
      }
    } else {
      // Plain filename pattern (no trailing /, no glob) — exact basename match
      if (pattern.startsWith('/')) {
        if (filePath === pattern.slice(1)) return true;
      } else {
        if (basename(filePath) === pattern) return true;
      }
    }
  }
  return false;
}

/** Find source files in a directory. Uses lstatSync to skip symlinks. */
function findSourceFiles(dir, recursive, langFilter) {
  const supported = langFilter
    ? mappings.filter(m => m.name === langFilter).flatMap(m => m.extensions)
    : allExtensions();
  const extSet = new Set(supported);
  const results = [];
  let entries;
  try {
    entries = readdirSync(dir);
  } catch (err) {
    console.error(`Warning: cannot read directory ${dir}: ${err.message}`);
    return results;
  }
  for (const entry of entries) {
    const full = join(dir, entry);
    let stat;
    try {
      stat = lstatSync(full);  // lstatSync: don't follow symlinks
    } catch (err) {
      console.error(`Warning: cannot stat ${full}: ${err.message}`);
      continue;  // Skip files we can't stat (EACCES, etc.)
    }
    if (stat.isSymbolicLink()) continue;  // Skip symlinks to prevent infinite loops
    if (stat.isDirectory()) {
      if (recursive && !EXCLUDE_DIRS.has(entry)) {
        results.push(...findSourceFiles(full, true, langFilter));
      }
    } else {
      const ext = extname(entry);
      if (extSet.has(ext) && !entry.endsWith('.d.ts')) {
        results.push(full);
      }
    }
  }
  return results;
}

/** Write content to file atomically (temp file + rename) */
function atomicWrite(filePath, content) {
  const tmpFile = filePath + `.tmp.${process.pid}`;
  writeFileSync(tmpFile, content);
  try {
    renameSync(tmpFile, filePath);
  } catch (e) {
    try { unlinkSync(tmpFile); } catch {}
    throw e;
  }
}

/** CLI entry point */
async function cli(args) {
  // Reserved flags — not yet implemented in v2
  const RESERVED_FLAGS = ['--deep', '--enrich', '--since', '--check', '--shard'];
  for (const flag of RESERVED_FLAGS) {
    if (args.includes(flag) || args.some(a => a.startsWith(flag + '='))) {
      console.error(`Error: ${flag} is not yet implemented in GDLC v2. See specs/GDLC-SPEC.md for roadmap.`);
      process.exit(1);
    }
  }

  const positional = args.filter(a => !a.startsWith('--'));
  const flags = Object.fromEntries(
    args.filter(a => a.startsWith('--')).map(a => {
      const eq = a.indexOf('=');
      return eq > 0 ? [a.slice(2, eq), a.slice(eq + 1)] : [a.slice(2), 'true'];
    })
  );

  if (flags.help) {
    const supported = mappings.map(m => `${m.name} (${m.extensions.join(', ')})`).join(', ');
    console.error(`Usage: src2gdlc <directory|file> [--output=FILE] [--recursive] [--lang=NAME] [--ignore-file=PATH]`);
    console.error(`Supported languages: ${supported}`);
    process.exit(0);
  }

  const target = positional[0];
  if (!target) {
    console.error('Usage: src2gdlc <directory|file> [--output=FILE] [--recursive] [--lang=NAME] [--ignore-file=PATH]');
    process.exit(1);
  }

  const outputFile = flags.output;
  const recursive = 'recursive' in flags;
  const langFilter = flags.lang;
  const ignoreFileFlag = flags['ignore-file'];

  if (!existsSync(target)) {
    console.error(`Error: ${target} does not exist`);
    process.exit(1);
  }

  // Validate --lang matches a known mapping
  if (langFilter && !mappings.find(m => m.name === langFilter)) {
    const known = mappings.map(m => m.name).join(', ');
    console.error(`Error: unknown language '${langFilter}'. Available: ${known}`);
    process.exit(1);
  }

  const stat = statSync(target);
  let files;
  if (stat.isDirectory()) {
    files = findSourceFiles(target, recursive, langFilter);
  } else {
    // Single-file mode: filter .d.ts files (same as directory scanning)
    if (target.endsWith('.d.ts')) {
      console.error(`Skipping declaration file: ${target}`);
      process.exit(0);
    }
    // Validate file extension is supported
    const ext = extname(target);
    if (!mappingForExt(ext)) {
      const known = allExtensions().join(', ');
      console.error(`Error: unsupported file type '${ext}'. Supported: ${known}`);
      process.exit(1);
    }
    files = [target];
  }

  // Load .gdlignore patterns — try git root first (project root), fall back to scan target
  let ignoreSearchDir;
  if (stat.isDirectory()) {
    try {
      ignoreSearchDir = execSync('git rev-parse --show-toplevel', {
        cwd: resolve(target), encoding: 'utf-8'
      }).trim();
    } catch {
      ignoreSearchDir = resolve(target);
    }
  } else {
    // Try git root first (project root), fall back to file's parent dir
    try {
      ignoreSearchDir = execSync('git rev-parse --show-toplevel', {
        cwd: resolve(target, '..'), encoding: 'utf-8'
      }).trim();
    } catch {
      ignoreSearchDir = resolve(target, '..');
    }
  }
  const ignoreFilePath = ignoreFileFlag || join(ignoreSearchDir, '.gdlignore');
  const ignorePatterns = readGdlignore(ignoreFilePath, 'gdlc');
  if (ignorePatterns.length > 0) {
    const baseDir = ignoreSearchDir;
    const before = files.length;
    files = files.filter(f => {
      const rel = relative(baseDir, resolve(f));
      return !shouldExclude(rel, ignorePatterns);
    });
    const excluded = before - files.length;
    if (excluded > 0) {
      console.error(`Excluded ${excluded} file(s) via .gdlignore`);
    }
  }

  const today = new Date().toISOString().slice(0, 10);

  // Empty project handling — produce valid empty GDLC when --output is specified
  if (files.length === 0) {
    if (outputFile) {
      const output = formatGdlcV2([], { sourceHash: '0000000', generated: today });
      atomicWrite(outputFile, output);
      console.error('No supported source files found. Wrote empty GDLC.');
    } else {
      console.error('No supported source files found in ' + target);
    }
    if (stat.isDirectory() && !recursive) {
      console.error('Hint: use --recursive to scan subdirectories.');
    }
    process.exit(0);
  }

  // Determine base directory for relative paths
  const baseDir = stat.isDirectory() ? resolve(target) : dirname(resolve(target));

  // Process all files — extract exports, imports, docstring
  const fileResults = [];
  for (const file of files) {
    const ext = extname(file);
    const mapping = mappingForExt(ext);
    if (!mapping) {
      console.error(`Warning: no mapping for ${ext}, skipping ${file}`);
      continue;
    }

    const isTsx = ext === '.tsx' || ext === '.jsx';
    let result;
    try {
      result = await extractFile(file, mapping, { isTsx });
    } catch (err) {
      console.error(`Error processing ${file}: ${err.message}`);
      continue;
    }

    // Determine langId with tsx/jsx override
    let langId = mapping.langId;
    if (ext === '.tsx') langId = 'tsx';
    else if (ext === '.jsx') langId = 'jsx';

    const relPath = relative(baseDir, resolve(file));
    fileResults.push({
      path: relPath,
      lang: langId,
      exports: result.exports,
      imports: result.imports,
      docstring: result.docstring,
    });
  }

  // Compute source hash from file contents
  const sourceHash = computeSourceHash(files.map(f => resolve(f)));

  // Format single GDLC v2 output
  const output = formatGdlcV2(fileResults, { sourceHash, generated: today });

  if (outputFile) {
    atomicWrite(outputFile, output);
    console.error(`Wrote: ${outputFile}`);
  } else {
    process.stdout.write(output);
  }
  console.error(`Processed ${fileResults.length} file(s).`);
}

const isMainModule = process.argv[1] && resolve(process.argv[1]) === resolve(fileURLToPath(import.meta.url));
if (isMainModule && process.argv.length > 2) {
  cli(process.argv.slice(2)).catch(err => {
    console.error(`Fatal: ${err.message}`);
    process.exit(1);
  });
}

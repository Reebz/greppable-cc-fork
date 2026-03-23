/**
 * shared.js — Language-agnostic GDLC v2 formatting and utilities
 */
import { readFileSync } from 'fs';
import path from 'path';
import { createHash } from 'crypto';

/** Escape pipe characters in GDLC field values */
export function escapePipe(value) {
  if (!value) return '';
  return value.replace(/\|/g, '\\|');
}

/**
 * Format v2 GDLC output.
 * @D descriptions are empty by default in the structural pass.
 * @param {{ path: string, lang: string, exports: string[], imports: string[], docstring: string }[]} files
 * @param {{ sourceHash: string, generated: string }} options
 * @returns {string}
 */
export function formatGdlcV2(files, options) {
  const lines = [];
  lines.push(`# @VERSION spec:gdlc v:2.0.0 generated:${options.generated} source:tree-sitter source-hash:${options.sourceHash}`);
  lines.push('# @FORMAT PATH|LANG|EXPORTS|IMPORTS|DESCRIPTION');
  lines.push('');

  // Group by directory
  const dirs = new Map();
  for (const f of files) {
    const dir = path.dirname(f.path);
    if (!dirs.has(dir)) dirs.set(dir, []);
    dirs.get(dir).push(f);
  }

  // Sort directories alphabetically for deterministic output
  const sortedDirs = [...dirs.entries()].sort((a, b) => a[0].localeCompare(b[0]));
  for (const [dir, dirFiles] of sortedDirs) {
    dirFiles.sort((a, b) => a.path.localeCompare(b.path));
    lines.push(`@D ${dir}|`);
    lines.push('');
    for (const f of dirFiles) {
      const exports = escapePipe(f.exports.join(','));
      const imports = escapePipe(f.imports.join(','));
      const desc = escapePipe(f.docstring || '');
      lines.push(`@F ${f.path}|${f.lang}|${exports}|${imports}|${desc}`);
    }
    lines.push('');
  }

  return lines.join('\n').trimEnd() + '\n';
}

/**
 * Compute SHA-256 hash of file contents, truncated to 7 chars.
 */
export function computeSourceHash(filePaths) {
  const hash = createHash('sha256');
  for (const fp of [...filePaths].sort()) {
    hash.update(readFileSync(fp));
  }
  return hash.digest('hex').slice(0, 7);
}

/** Compute hash from already-read content (avoids double file I/O) */
export function computeSourceHashFromContent(content) {
  return createHash('sha256').update(content).digest('hex').slice(0, 7);
}

/**
 * Extract first line/sentence from a doc comment block.
 * Strips comment delimiters and returns first sentence.
 */
export function normalizeDescription(text) {
  if (!text) return '';
  let cleaned = text
    .replace(/^\/\*\*?\s*|\s*\*\/$/g, '')
    .replace(/^\s*\/\/\/?\s*/gm, '')
    .replace(/^\s*\*\s?/gm, '')
    .trim();
  if (!cleaned) return '';
  const lines = cleaned.split('\n');
  let firstLine = '';
  for (const line of lines) {
    const trimmed = line.trim();
    if (trimmed && !trimmed.startsWith('@')) {
      firstLine = trimmed;
      break;
    }
  }
  if (!firstLine) return '';
  const firstSentence = firstLine.match(/^[^.!?]+[.!?]?/)?.[0] || firstLine;
  return firstSentence.trim();
}

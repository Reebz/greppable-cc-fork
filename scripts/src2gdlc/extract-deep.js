/**
 * extract-deep.js — Member-level extraction via tree-sitter (GDLC v2.1)
 *
 * Extracts function/method declarations with signatures and call expressions.
 * Walks into function bodies (unlike extract.js which only visits top-level).
 */
import { readFileSync } from 'fs';
import { Parser } from 'web-tree-sitter';
import { ensureInit, loadLanguage } from './extract.js';

/**
 * @typedef {Object} MemberRecord
 * @property {string} filePath - relative path
 * @property {string} symbol - qualified name
 * @property {string} kind - fn|method|constructor|const|prop
 * @property {string} signature - (params) -> return_type
 * @property {string[]} calls - called symbols
 */

/**
 * Extract member-level records from a source file.
 * @param {string} filePath - Absolute path to source file
 * @param {object} mapping - Language mapping config (must have getDeclarations)
 * @param {object} [options] - Options (isTsx, stoplist, relPath)
 * @returns {Promise<MemberRecord[]>}
 */
export async function extractFileDeep(filePath, mapping, options = {}) {
  if (!mapping.getDeclarations) {
    return []; // Language doesn't support deep extraction yet
  }

  await ensureInit();
  const wasmFile = (options.isTsx && mapping.tsxWasmFile) ? mapping.tsxWasmFile : mapping.wasmFile;
  const lang = await loadLanguage(wasmFile);

  const parser = new Parser();
  parser.setLanguage(lang);

  let source = readFileSync(filePath, 'utf-8');
  if (source.charCodeAt(0) === 0xFEFF) source = source.slice(1);
  if (source.includes('\0')) return [];

  let tree;
  try {
    tree = parser.parse(source);
  } catch (err) {
    console.error(`Warning: deep parse failed for ${filePath}: ${err.message}`);
    return [];
  }
  if (!tree || !tree.rootNode) return [];

  const relPath = options.relPath || filePath;
  const stoplist = options.stoplist || new Set();
  const records = [];

  // Delegate to the mapping's deep extraction
  const declarations = mapping.getDeclarations(tree.rootNode, source);
  if (!declarations) return [];

  for (const decl of declarations) {
    // Extract calls from the function body
    let calls = [];
    if (decl.bodyNode && mapping.getCallExpressions) {
      const rawCalls = mapping.getCallExpressions(decl.bodyNode, source, decl.classPrefix);
      // Filter: remove stoplist, remove self-references, deduplicate
      // For qualified calls (e.g., JSON.parse), check if any part is in stoplist
      const seen = new Set();
      for (const call of rawCalls) {
        const parts = call.split('.');
        const inStoplist = parts.some(p => stoplist.has(p));
        if (!inStoplist && call !== decl.symbol && !seen.has(call)) {
          seen.add(call);
          calls.push(call);
        }
      }
    }

    records.push({
      filePath: relPath,
      symbol: decl.symbol,
      kind: decl.kind,
      signature: decl.signature || '',
      calls,
    });
  }

  return records;
}

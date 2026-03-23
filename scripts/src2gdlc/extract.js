/**
 * extract.js — File-level extraction via tree-sitter (GDLC v2)
 *
 * Extracts exports, imports, and file-level docstring from a single source file.
 * Only walks root.namedChildren (top-level) — never recurses into class/function bodies.
 */
import { readFileSync } from 'fs';
import { Parser, Language } from 'web-tree-sitter';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const WASM_DIR = resolve(__dirname, 'grammars');

let initPromise = null;
const languageCache = new Map();

async function ensureInit() {
  if (!initPromise) {
    initPromise = Parser.init().catch(err => {
      initPromise = null;
      throw new Error(`WASM runtime init failed: ${err.message}`);
    });
  }
  return initPromise;
}

async function loadLanguage(wasmFile) {
  if (!languageCache.has(wasmFile)) {
    const wasmPath = resolve(WASM_DIR, wasmFile);
    languageCache.set(wasmFile, Language.load(wasmPath).catch(err => {
      languageCache.delete(wasmFile);
      throw new Error(`Failed to load grammar '${wasmFile}': ${err.message}`);
    }));
  }
  return languageCache.get(wasmFile);
}

/**
 * Extract file-level metadata: exported symbols, imports, and docstring.
 * @param {string} filePath - Path to source file
 * @param {object} mapping - Language mapping config
 * @param {object} [options] - Options (isTsx: boolean)
 * @returns {Promise<{ exports: string[], imports: string[], docstring: string }>}
 */
export async function extractFile(filePath, mapping, options = {}) {
  await ensureInit();
  const wasmFile = (options.isTsx && mapping.tsxWasmFile) ? mapping.tsxWasmFile : mapping.wasmFile;
  const lang = await loadLanguage(wasmFile);
  const parser = new Parser();
  parser.setLanguage(lang);

  let source = readFileSync(filePath, 'utf-8');
  // Strip UTF-8 BOM
  if (source.charCodeAt(0) === 0xFEFF) source = source.slice(1);
  // Skip binary files
  if (source.includes('\0')) {
    return { exports: [], imports: [], docstring: '' };
  }

  let tree;
  try {
    tree = parser.parse(source);
  } catch (err) {
    console.error(`Warning: parse failed for ${filePath}: ${err.message}`);
    return { exports: [], imports: [], docstring: '' };
  }
  if (!tree || !tree.rootNode) {
    console.error(`Warning: parse returned null for ${filePath}`);
    return { exports: [], imports: [], docstring: '' };
  }
  const root = tree.rootNode;

  const exports = [];
  const imports = [];
  let docstring = '';

  for (const child of root.namedChildren) {
    // Docstring: first doc comment at file level
    if (!docstring && mapping.isDocComment?.(child)) {
      docstring = mapping.getDocText?.(child) || '';
    }
    // Exports: top-level exported/public declarations
    const exportNames = mapping.getExports?.(child);
    if (exportNames) {
      exports.push(...(Array.isArray(exportNames) ? exportNames : [exportNames]));
    }
    // Imports: import statements
    const importModules = mapping.getImportModule?.(child);
    if (importModules) {
      imports.push(...(Array.isArray(importModules) ? importModules : [importModules]));
    }
  }

  return {
    exports: [...new Set(exports)],
    imports: [...new Set(imports)],
    docstring: docstring.trim(),
  };
}

export { ensureInit, loadLanguage };

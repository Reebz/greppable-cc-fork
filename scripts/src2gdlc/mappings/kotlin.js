/**
 * Kotlin language mapping for src2gdlc v2.
 *
 * Simplified interface: getExports, getImportModule, isDocComment, getDocText.
 * Node types verified against tree-sitter-kotlin grammar (self-built via build-grammars.sh).
 *
 * Key: tree-sitter-kotlin has NO named fields — all access via descendantsOfType
 * and direct child iteration.
 */
import { normalizeDescription } from '../shared.js';

/** Check for private or internal visibility_modifier among direct children.
 *  ABI 14 grammar wraps visibility_modifier inside a modifiers container. */
function isNonPublic(node) {
  for (let i = 0; i < node.childCount; i++) {
    const c = node.child(i);
    if (!c) continue;
    // Direct visibility_modifier (older ABI)
    if (c.type === 'visibility_modifier' && (c.text === 'private' || c.text === 'internal')) return true;
    // ABI 14: modifiers container wrapping visibility_modifier
    if (c.type === 'modifiers') {
      for (let j = 0; j < c.childCount; j++) {
        const m = c.child(j);
        if (m && m.type === 'visibility_modifier' && (m.text === 'private' || m.text === 'internal')) return true;
      }
    }
  }
  return false;
}

export default {
  wasmFile: 'tree-sitter-kotlin.wasm',
  extensions: ['.kt', '.kts'],
  name: 'kotlin',
  langId: 'kt',

  getExports(node) {
    // Top-level function
    if (node.type === 'function_declaration') {
      if (isNonPublic(node)) return null;
      const nameNode = node.descendantsOfType('simple_identifier')[0];
      return nameNode ? nameNode.text : null;
    }
    // Class (includes data class, sealed class, enum class)
    if (node.type === 'class_declaration') {
      if (isNonPublic(node)) return null;
      const nameNode = node.descendantsOfType('type_identifier')[0];
      return nameNode ? nameNode.text : null;
    }
    // Object declaration (singleton, companion)
    if (node.type === 'object_declaration') {
      if (isNonPublic(node)) return null;
      const nameNode = node.descendantsOfType('type_identifier')[0];
      return nameNode ? nameNode.text : null;
    }
    // Top-level property
    if (node.type === 'property_declaration') {
      if (isNonPublic(node)) return null;
      const nameNode = node.descendantsOfType('simple_identifier')[0];
      return nameNode ? nameNode.text : null;
    }
    return null;
  },

  getImportModule(node) {
    // import_list wraps multiple import_header children
    if (node.type !== 'import_list') return null;
    const headers = node.descendantsOfType('import_header');
    if (headers.length === 0) return null;
    const names = [];
    for (const header of headers) {
      const ident = header.descendantsOfType('identifier')[0];
      if (ident) {
        const fullPath = ident.text;
        const parts = fullPath.split('.');
        const imported = parts[parts.length - 1];
        if (imported) names.push(imported);
      }
    }
    return names.length > 0 ? names : null;
  },

  isDocComment(node) {
    return node.type === 'multiline_comment' && node.text.startsWith('/**');
  },

  getDocText(node) {
    return normalizeDescription(node.text);
  },
};

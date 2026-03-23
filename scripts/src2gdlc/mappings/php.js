/**
 * PHP language mapping for src2gdlc v2.
 *
 * Simplified interface: getExports, getImportModule, isDocComment, getDocText.
 * Node types verified against tree-sitter-php grammar (self-built via build-grammars.sh).
 */
import { normalizeDescription } from '../shared.js';

export default {
  wasmFile: 'tree-sitter-php.wasm',
  extensions: ['.php'],
  name: 'php',
  langId: 'php',

  getExports(node) {
    // Class, interface, enum, trait declarations
    if (
      node.type === 'class_declaration' ||
      node.type === 'interface_declaration' ||
      node.type === 'enum_declaration' ||
      node.type === 'trait_declaration'
    ) {
      const nameNode = node.childForFieldName('name');
      return nameNode ? nameNode.text : null;
    }
    // Top-level function
    if (node.type === 'function_definition') {
      const nameNode = node.childForFieldName('name');
      return nameNode ? nameNode.text : null;
    }
    // Namespace definitions are containers, not exports
    if (node.type === 'namespace_definition') {
      return null;
    }
    return null;
  },

  getImportModule(node) {
    // namespace_use_declaration -> namespace_use_clause descendants
    if (node.type !== 'namespace_use_declaration') return null;
    const clauses = node.descendantsOfType('namespace_use_clause');
    if (clauses.length === 0) return null;
    const names = [];
    for (const clause of clauses) {
      const qname = clause.descendantsOfType('qualified_name')[0]
        || clause.descendantsOfType('name')[0];
      if (qname) {
        const fullName = qname.text;
        // PHP namespace separator is \ — take last segment
        const parts = fullName.split('\\');
        const imported = parts[parts.length - 1];
        if (imported) names.push(imported);
      }
    }
    return names.length > 0 ? names : null;
  },

  isDocComment(node) {
    return node.type === 'comment' && node.text.startsWith('/**');
  },

  getDocText(node) {
    return normalizeDescription(node.text);
  },
};

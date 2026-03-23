import { normalizeDescription } from '../shared.js';

/** Check if a node's modifiers contain 'public' */
function hasPublicModifier(node) {
  const mods = node.childForFieldName?.('modifiers');
  if (!mods) {
    // Try direct child search for modifiers node
    for (const child of node.children || []) {
      if (child.type === 'modifiers') {
        return child.text.includes('public');
      }
    }
    return false;
  }
  return mods.text.includes('public');
}

export default {
  wasmFile: 'tree-sitter-java.wasm',
  extensions: ['.java'],
  name: 'java',
  langId: 'java',

  getExports(node) {
    // class_declaration, interface_declaration, enum_declaration with public modifier
    if (
      node.type === 'class_declaration' ||
      node.type === 'interface_declaration' ||
      node.type === 'enum_declaration'
    ) {
      if (!hasPublicModifier(node)) return null;
      const nameNode = node.childForFieldName?.('name');
      return nameNode ? nameNode.text : null;
    }

    return null;
  },

  getImportModule(node) {
    if (node.type !== 'import_declaration') return null;
    // Find scoped_identifier and walk to root scope for top-level package
    const scopedIds = node.descendantsOfType?.('scoped_identifier') || [];
    const scopedId = scopedIds[0];
    if (scopedId) {
      let current = scopedId;
      while (current.childForFieldName?.('scope')?.type === 'scoped_identifier') {
        current = current.childForFieldName('scope');
      }
      const topScope = current.childForFieldName?.('scope');
      return topScope ? topScope.text : current.text;
    }
    // Fallback: bare identifier
    const idents = node.descendantsOfType?.('identifier') || [];
    if (idents[0]) return idents[0].text;
    return null;
  },

  isDocComment(node) {
    return node.type === 'block_comment' && node.text.startsWith('/**');
  },

  getDocText(node) {
    return normalizeDescription(node.text);
  },
};

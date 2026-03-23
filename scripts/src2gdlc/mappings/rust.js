import { normalizeDescription } from '../shared.js';

export default {
  wasmFile: 'tree-sitter-rust.wasm',
  extensions: ['.rs'],
  name: 'rust',
  langId: 'rs',

  getExports(node) {
    // Only top-level nodes with a visibility_modifier child (pub) are exports
    if (!hasVisibilityModifier(node)) return null;

    switch (node.type) {
      case 'function_item': {
        const name = node.childForFieldName('name');
        return name ? name.text : null;
      }
      case 'struct_item':
      case 'enum_item':
      case 'trait_item': {
        const name = node.childForFieldName('name');
        return name ? name.text : null;
      }
      case 'impl_item': {
        const typeNode = node.childForFieldName('type');
        return typeNode ? typeNode.text : null;
      }
      case 'const_item':
      case 'static_item':
      case 'type_item': {
        const name = node.childForFieldName('name');
        return name ? name.text : null;
      }
      default:
        return null;
    }
  },

  getImportModule(node) {
    if (node.type !== 'use_declaration') return null;
    const arg = node.childForFieldName('argument');
    if (!arg) return null;
    const rootCrate = getFirstIdentifier(arg);
    return rootCrate || null;
  },

  isDocComment(node) {
    return (node.type === 'line_comment' && node.text.startsWith('///'))
      || (node.type === 'block_comment' && node.text.startsWith('/**'));
  },

  getDocText(node) {
    return normalizeDescription(node.text);
  },
};

/** Check if a node has a visibility_modifier as a direct child */
function hasVisibilityModifier(node) {
  for (let i = 0; i < node.childCount; i++) {
    if (node.child(i).type === 'visibility_modifier') return true;
  }
  return false;
}

/**
 * Recursively extract the first identifier (root crate) from a use path.
 * Handles: scoped_identifier, scoped_use_list, use_as_clause, use_wildcard, identifier.
 */
function getFirstIdentifier(node) {
  if (!node) return '';
  if (node.type === 'identifier') return node.text;
  if (node.type === 'crate') return 'crate';
  if (node.type === 'self') return 'self';
  if (node.type === 'super') return 'super';

  if (node.type === 'scoped_identifier') {
    const path = node.childForFieldName('path');
    if (path) return getFirstIdentifier(path);
    const name = node.childForFieldName('name');
    return name ? name.text : '';
  }

  if (node.type === 'scoped_use_list') {
    const path = node.childForFieldName('path');
    if (path) return getFirstIdentifier(path);
    return '';
  }

  if (node.type === 'use_as_clause') {
    const path = node.childForFieldName('path');
    if (path) return getFirstIdentifier(path);
    return '';
  }

  if (node.type === 'use_wildcard') {
    for (let i = 0; i < node.namedChildCount; i++) {
      const result = getFirstIdentifier(node.namedChild(i));
      if (result) return result;
    }
    return '';
  }

  // Fallback: try first named child
  if (node.namedChildCount > 0) {
    return getFirstIdentifier(node.namedChild(0));
  }
  return '';
}

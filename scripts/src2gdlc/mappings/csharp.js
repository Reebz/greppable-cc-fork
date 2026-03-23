import { normalizeDescription } from '../shared.js';

export default {
  wasmFile: 'tree-sitter-c_sharp.wasm',
  extensions: ['.cs'],
  name: 'csharp',
  langId: 'cs',

  getExports(node) {
    switch (node.type) {
      case 'class_declaration':
      case 'interface_declaration':
      case 'enum_declaration':
      case 'struct_declaration': {
        if (!hasPublicModifier(node)) return null;
        const name = node.childForFieldName('name');
        return name ? name.text : null;
      }
      case 'namespace_declaration':
        // Namespace is a container, not an export
        return null;
      default:
        return null;
    }
  },

  getImportModule(node) {
    if (node.type !== 'using_directive') return null;
    const qname = node.descendantsOfType('qualified_name')[0]
      || node.descendantsOfType('identifier')[0];
    if (!qname) return null;
    const fullName = qname.text;
    return fullName.split('.')[0];
  },

  isDocComment(node) {
    return node.type === 'comment' && node.text.trimStart().startsWith('///');
  },

  getDocText(node) {
    const text = node.text;
    // Strip /// prefix and XML tags, extract summary content
    const cleaned = text
      .split('\n')
      .filter(l => l.trimStart().startsWith('///'))
      .map(l => l.replace(/^\s*\/\/\/\s?/, ''))
      .join(' ')
      .replace(/<\/?summary>/g, '')
      .replace(/<[^>]+>/g, '')
      .trim();
    if (!cleaned) return '';
    const firstSentence = cleaned.match(/^[^.!?]+[.!?]?/)?.[0] || cleaned;
    return firstSentence.trim();
  },
};

/** Check if a node has a 'public' modifier as a direct named child */
function hasPublicModifier(node) {
  for (let i = 0; i < node.namedChildCount; i++) {
    const child = node.namedChild(i);
    if (child.type === 'modifier' && child.text === 'public') return true;
  }
  return false;
}

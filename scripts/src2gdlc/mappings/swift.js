/**
 * Swift language mapping for src2gdlc v2.
 *
 * Simplified interface: getExports, getImportModule, isDocComment, getDocText.
 * Node types verified against tree-sitter-swift grammar (self-built via build-grammars.sh).
 *
 * Visibility: public, open, internal (default) are exported.
 * private and fileprivate are not exported.
 */

/** Check for private/fileprivate modifier among direct children.
 *  ABI 14 grammar uses 'modifier', older grammars use 'visibility_modifier'. */
function isPrivateOrFileprivate(node) {
  for (let i = 0; i < node.childCount; i++) {
    const c = node.child(i);
    if (c && (c.type === 'visibility_modifier' || c.type === 'modifier')) {
      const text = c.text;
      if (text === 'private' || text === 'fileprivate') return true;
    }
  }
  return false;
}

/** Extract type name from node text when parse tree has ERROR nodes (e.g. inheritance). */
function extractNameFromText(node) {
  const firstLine = node.text.split('\n')[0];
  const match = firstLine.match(/(?:class|struct|enum|protocol)\s+(\w+)/);
  return match ? match[1] : null;
}

export default {
  wasmFile: 'tree-sitter-swift.wasm',
  extensions: ['.swift'],
  name: 'swift',
  langId: 'swift',

  getExports(node) {
    // Function declaration
    if (node.type === 'function_declaration') {
      if (isPrivateOrFileprivate(node)) return null;
      const nameNode = node.childForFieldName('name');
      return nameNode ? nameNode.text : null;
    }
    // Class, struct, enum, protocol declarations
    if (['class_declaration', 'protocol_declaration', 'struct_declaration', 'enum_declaration'].includes(node.type)) {
      if (isPrivateOrFileprivate(node)) return null;
      // Try field name first, fall back to identifier child, then text extraction
      // for cases where inheritance syntax produces ERROR nodes (ABI 14+ compat)
      const nameNode = node.childForFieldName('name')
        || node.namedChildren.find(c => c.type === 'type_identifier')
        || node.namedChildren.find(c => c.type === 'identifier');
      const name = nameNode ? nameNode.text : null;
      // If identifier matched a superclass/protocol name (ERROR swallowed the real name),
      // fall back to text extraction
      if (!name || node.namedChildren.some(c => c.type === 'ERROR')) {
        return extractNameFromText(node) || name;
      }
      return name;
    }
    return null;
  },

  getImportModule(node) {
    // import_declaration -> identifier descendant
    if (node.type !== 'import_declaration') return null;
    const ident = node.descendantsOfType('identifier')[0];
    return ident ? ident.text : null;
  },

  isDocComment(node) {
    return node.type === 'comment' && node.text.trimStart().startsWith('///');
  },

  getDocText(node) {
    // Strip /// prefix from each line, join, return first sentence
    const lines = node.text.split('\n');
    const docLines = lines.filter(l => l.trimStart().startsWith('///'));
    if (docLines.length === 0) return '';
    const cleaned = docLines
      .map(l => l.replace(/^\s*\/\/\/\s?/, ''))
      .join(' ')
      .trim();
    if (!cleaned) return '';
    const firstSentence = cleaned.match(/^[^.!?]+[.!?]?/)?.[0] || cleaned;
    return firstSentence.trim();
  },
};

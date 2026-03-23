/**
 * Ruby language mapping for src2gdlc v2.
 *
 * Simplified interface: getExports, getImportModule, isDocComment, getDocText.
 * Node types verified against tree-sitter-ruby grammar (self-built via build-grammars.sh).
 */

export default {
  wasmFile: 'tree-sitter-ruby.wasm',
  extensions: ['.rb'],
  name: 'ruby',
  langId: 'rb',

  getExports(node) {
    // Top-level class: class Foo
    if (node.type === 'class') {
      const nameNode = node.childForFieldName('name');
      return nameNode ? nameNode.text : null;
    }
    // Top-level module: module Bar
    if (node.type === 'module') {
      const nameNode = node.childForFieldName('name');
      return nameNode ? nameNode.text : null;
    }
    // Top-level method: def foo
    if (node.type === 'method') {
      const nameNode = node.childForFieldName('name');
      if (!nameNode) return null;
      const name = nameNode.text;
      // Skip initializers
      if (name === 'initialize') return null;
      return name;
    }
    // Singleton method: def self.foo
    if (node.type === 'singleton_method') {
      const nameNode = node.childForFieldName('name');
      if (!nameNode) return null;
      const name = nameNode.text;
      if (name === 'initialize') return null;
      return name;
    }
    return null;
  },

  getImportModule(node) {
    // Ruby imports are call nodes where method is require or require_relative
    if (node.type !== 'call') return null;
    const methodNode = node.childForFieldName('method');
    if (!methodNode) return null;
    const methodName = methodNode.text;
    if (methodName !== 'require' && methodName !== 'require_relative') return null;
    const args = node.childForFieldName('arguments');
    if (!args) return null;
    const strNode = args.descendantsOfType('string_content')[0];
    if (!strNode) return null;
    // Take last path segment: 'foo/bar/baz' -> 'baz'
    const parts = strNode.text.split('/');
    return parts[parts.length - 1];
  },

  isDocComment(node) {
    return node.type === 'comment' && node.text.trimStart().startsWith('#');
  },

  getDocText(node) {
    // Strip # prefix, return first sentence
    const stripped = node.text.replace(/^\s*#\s?/gm, '').trim();
    if (!stripped) return '';
    const firstSentence = stripped.match(/^[^.!?]+[.!?]?/)?.[0] || stripped;
    return firstSentence.trim();
  },
};

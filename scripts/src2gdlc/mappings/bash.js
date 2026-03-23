/**
 * Bash/Shell language mapping for src2gdlc v2
 */
import { normalizeDescription } from '../shared.js';

export default {
  wasmFile: 'tree-sitter-bash.wasm',
  extensions: ['.sh', '.bash'],
  name: 'bash',
  langId: 'sh',

  getExports(node) {
    if (node.type === 'function_definition') {
      const nameNode = node.childForFieldName('name');
      if (!nameNode) return null;
      const name = nameNode.text;
      // Skip internal functions by convention
      if (name.startsWith('_')) return null;
      return name;
    }
    return null;
  },

  getImportModule(node) {
    if (node.type !== 'command') return null;
    const children = node.namedChildren;
    if (children.length < 2) return null;
    // tree-sitter-bash uses 'command_name' for the command
    const cmdNameNode = children[0];
    if (!cmdNameNode || cmdNameNode.type !== 'command_name') return null;
    const cmdName = cmdNameNode.text;
    // Match 'source' or '.' builtin
    if (cmdName !== 'source' && cmdName !== '.') return null;
    // Get the argument — the file being sourced
    const arg = children[1];
    if (!arg) return null;
    const argText = arg.text;
    // For 'word' type (bare paths): extract basename directly
    if (arg.type === 'word') {
      const parts = argText.split('/');
      return parts[parts.length - 1];
    }
    // For 'string' type (quoted): check for variable-only paths
    if (arg.type === 'string') {
      const cleaned = argText.replace(/^["']|["']$/g, '');
      // If it contains $, try to extract last path segment
      if (cleaned.includes('$')) {
        const match = cleaned.match(/\/([^/$]+)$/);
        if (match) return match[1];
        return null;
      }
      // Pure string path
      const parts = cleaned.split('/');
      return parts[parts.length - 1];
    }
    return null;
  },

  isDocComment(node) {
    if (node.type !== 'comment') return false;
    const text = node.text;
    // Skip shebang lines
    if (text.startsWith('#!')) return false;
    // Skip empty comments
    const stripped = text.replace(/^#\s*/, '').trim();
    return stripped.length > 0;
  },

  getDocText(node) {
    if (node.type !== 'comment') return null;
    const text = node.text.replace(/^#\s*/, '').trim();
    if (!text) return null;
    return normalizeDescription(text);
  },
};

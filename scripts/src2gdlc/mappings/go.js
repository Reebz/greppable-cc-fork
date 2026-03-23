import { normalizeDescription } from '../shared.js';

/** Check if a name starts with an uppercase letter (Go export convention) */
function isCapitalized(name) {
  if (!name) return false;
  const first = name.charAt(0);
  return first === first.toUpperCase() && first !== first.toLowerCase();
}

export default {
  wasmFile: 'tree-sitter-go.wasm',
  extensions: ['.go'],
  name: 'go',
  langId: 'go',

  getExports(node) {
    // Capitalized function_declaration
    if (node.type === 'function_declaration') {
      const nameNode = node.childForFieldName?.('name');
      if (nameNode && isCapitalized(nameNode.text)) return nameNode.text;
      return null;
    }

    // Capitalized method_declaration
    if (node.type === 'method_declaration') {
      const nameNode = node.childForFieldName?.('name');
      if (nameNode && isCapitalized(nameNode.text)) return nameNode.text;
      return null;
    }

    // type_declaration: iterate type_spec children, export capitalized names
    if (node.type === 'type_declaration') {
      const names = [];
      for (const child of node.namedChildren) {
        if (child.type === 'type_spec') {
          const nameNode = child.childForFieldName?.('name');
          if (nameNode && isCapitalized(nameNode.text)) names.push(nameNode.text);
        }
      }
      return names.length > 0 ? names : null;
    }

    // const_declaration: iterate const_spec children, export capitalized names
    if (node.type === 'const_declaration') {
      const names = [];
      for (const child of node.namedChildren) {
        if (child.type === 'const_spec') {
          const nameNode = child.childForFieldName?.('name');
          if (nameNode && isCapitalized(nameNode.text)) names.push(nameNode.text);
        }
      }
      return names.length > 0 ? names : null;
    }

    return null;
  },

  getImportModule(node) {
    if (node.type !== 'import_declaration') return null;
    const specs = node.descendantsOfType?.('import_spec') || [];
    const modules = [];
    for (const spec of specs) {
      const pathNode = spec.childForFieldName?.('path');
      if (!pathNode) continue;
      const importPath = pathNode.text.replace(/^["']|["']$/g, '');
      const segments = importPath.split('/');
      modules.push(segments[segments.length - 1]);
    }
    return modules.length > 0 ? modules : null;
  },

  isDocComment(node) {
    return node.type === 'comment' && node.text.startsWith('//');
  },

  getDocText(node) {
    return normalizeDescription(node.text);
  },
};

import { normalizeDescription } from '../shared.js';

export default {
  wasmFile: 'tree-sitter-python.wasm',
  extensions: ['.py'],
  name: 'python',
  langId: 'py',

  getExports(node) {
    // Python: all top-level function_definition and class_definition that don't start with _
    // Also handle decorated_definition wrappers
    let target = node;
    if (node.type === 'decorated_definition') {
      // Unwrap to get the inner definition
      target = node.namedChildren.find(c =>
        c.type === 'function_definition' || c.type === 'class_definition'
      );
      if (!target) return null;
    }

    if (target.type === 'function_definition' || target.type === 'class_definition') {
      const nameNode = target.childForFieldName?.('name');
      if (!nameNode) return null;
      const name = nameNode.text;
      if (name.startsWith('_')) return null;
      return name;
    }

    return null;
  },

  getImportModule(node) {
    // import os / import os.path
    if (node.type === 'import_statement') {
      const modules = [];
      for (const child of node.namedChildren) {
        if (child.type === 'dotted_name') {
          modules.push(child.text.split('.')[0]);
        } else if (child.type === 'aliased_import') {
          const nameNode = child.childForFieldName?.('name');
          if (nameNode) modules.push(nameNode.text.split('.')[0]);
        }
      }
      return modules.length > 0 ? modules : null;
    }

    // from pathlib import Path
    if (node.type === 'import_from_statement') {
      const moduleNameNode = node.childForFieldName?.('module_name');
      if (moduleNameNode) {
        return moduleNameNode.text.split('.')[0];
      }
      return null;
    }

    return null;
  },

  isDocComment(node) {
    // Python docstrings: expression_statement whose first child is a string (triple-quoted)
    if (node.type !== 'expression_statement') return false;
    const first = node.namedChildren[0];
    return first?.type === 'string' && /^['\"]{3}/.test(first.text);
  },

  getDocText(node) {
    const str = node.namedChildren[0];
    if (!str) return '';
    const text = str.text.replace(/^['\"]{3}|['\"]{3}$/g, '').trim();
    return normalizeDescription(text);
  },
};

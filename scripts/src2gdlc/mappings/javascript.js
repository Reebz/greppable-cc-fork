import { normalizeDescription } from '../shared.js';

export default {
  wasmFile: 'tree-sitter-javascript.wasm',
  extensions: ['.js', '.jsx', '.mjs', '.cjs'],
  name: 'javascript',
  langId: 'js',

  getExports(node) {
    // ESM: export function foo / export class Bar / export const x / export default / export { name }
    if (node.type === 'export_statement') {
      const names = [];
      const decl = node.namedChildren.find(c =>
        ['function_declaration', 'class_declaration', 'lexical_declaration'].includes(c.type)
      );
      if (decl) {
        if (decl.type === 'lexical_declaration') {
          for (const declarator of decl.namedChildren) {
            const nameNode = declarator.childForFieldName?.('name');
            if (nameNode) names.push(nameNode.text);
          }
        } else {
          const nameNode = decl.childForFieldName?.('name');
          if (nameNode) names.push(nameNode.text);
        }
      }
      // Re-export: export { foo, bar }
      for (const child of node.namedChildren) {
        if (child.type === 'export_clause') {
          for (const spec of child.namedChildren) {
            if (spec.type === 'export_specifier') {
              const alias = spec.childForFieldName?.('alias');
              const name = spec.childForFieldName?.('name');
              names.push((alias || name)?.text);
            }
          }
        }
      }
      // export default
      if (node.text.startsWith('export default') && names.length === 0) {
        names.push('default');
      }
      return names.length > 0 ? names.filter(Boolean) : null;
    }

    // CommonJS: module.exports = ...
    if (node.type === 'expression_statement') {
      const expr = node.namedChildren[0];
      if (expr?.type === 'assignment_expression') {
        const left = expr.childForFieldName?.('left');
        if (left?.type === 'member_expression' && left.text === 'module.exports') {
          return 'default';
        }
      }
    }

    return null;
  },

  getImportModule(node) {
    // ESM: import ... from 'module'
    if (node.type === 'import_statement') {
      const source = node.childForFieldName?.('source');
      if (!source) return null;
      const raw = source.text.replace(/['"]/g, '');
      if (raw.startsWith('.')) {
        const parts = raw.split('/');
        return parts[parts.length - 1];
      }
      if (raw.startsWith('@')) {
        return raw.split('/').slice(0, 2).join('/');
      }
      return raw.split('/')[0];
    }

    // CommonJS: require('module')
    if (node.type === 'expression_statement' || node.type === 'lexical_declaration' || node.type === 'variable_declaration') {
      const calls = node.descendantsOfType?.('call_expression') || [];
      const modules = [];
      for (const call of calls) {
        const fn = call.childForFieldName?.('function');
        if (fn?.text !== 'require') continue;
        const args = call.childForFieldName?.('arguments');
        if (!args) continue;
        const strNode = args.descendantsOfType?.('string')[0];
        if (!strNode) continue;
        const raw = strNode.text.replace(/['"]/g, '');
        if (raw.startsWith('.')) {
          const parts = raw.split('/');
          modules.push(parts[parts.length - 1]);
        } else if (raw.startsWith('@')) {
          modules.push(raw.split('/').slice(0, 2).join('/'));
        } else {
          modules.push(raw.split('/')[0]);
        }
      }
      return modules.length > 0 ? modules : null;
    }

    return null;
  },

  isDocComment(node) {
    return node.type === 'comment' && node.text.startsWith('/**');
  },

  getDocText(node) {
    return normalizeDescription(node.text);
  },
};

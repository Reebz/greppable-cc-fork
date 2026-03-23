import { normalizeDescription } from '../shared.js';

export default {
  wasmFile: 'tree-sitter-typescript.wasm',
  tsxWasmFile: 'tree-sitter-tsx.wasm',
  extensions: ['.ts', '.tsx'],
  name: 'typescript',
  langId: 'ts',

  getExports(node) {
    if (node.type !== 'export_statement') return null;
    const names = [];
    // Named export: export function foo / export class Bar / export type Baz
    const decl = node.namedChildren.find(c =>
      ['function_declaration', 'class_declaration', 'type_alias_declaration',
       'interface_declaration', 'enum_declaration', 'lexical_declaration'].includes(c.type)
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
  },

  getImportModule(node) {
    if (node.type !== 'import_statement') return null;
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
  },

  isDocComment(node) {
    return node.type === 'comment' && node.text.startsWith('/**');
  },

  getDocText(node) {
    return normalizeDescription(node.text);
  },
};

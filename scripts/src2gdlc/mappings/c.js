import { normalizeDescription } from '../shared.js';

export default {
  wasmFile: 'tree-sitter-c.wasm',
  extensions: ['.c', '.h'],
  name: 'c',
  langId: 'c',

  getExports(node) {
    if (node.type === 'function_definition') {
      // Static functions are internal, not exported
      const storageSpecs = node.descendantsOfType('storage_class_specifier');
      if (storageSpecs.some(s => s.text === 'static')) return null;
      // Unwrap: function_definition → declarator → function_declarator → declarator (name)
      let funcDecl = node.childForFieldName('declarator');
      if (funcDecl?.type === 'pointer_declarator') {
        for (let c = 0; c < funcDecl.namedChildCount; c++) {
          if (funcDecl.namedChild(c).type === 'function_declarator') {
            funcDecl = funcDecl.namedChild(c);
            break;
          }
        }
      }
      const nameNode = funcDecl?.childForFieldName('declarator');
      return nameNode ? nameNode.text : null;
    }

    if (node.type === 'type_definition') {
      // typedef struct { ... } Name; — last type_identifier is the name
      const declarators = node.descendantsOfType('type_identifier');
      const lastDecl = declarators[declarators.length - 1];
      return lastDecl ? lastDecl.text : null;
    }

    return null;
  },

  getImportModule(node) {
    if (node.type !== 'preproc_include') return null;
    const pathNode = node.childForFieldName('path')
      || node.descendantsOfType('system_lib_string')[0]
      || node.descendantsOfType('string_literal')[0];
    if (!pathNode) return null;
    const raw = pathNode.text.replace(/^[<"]|[>"]$/g, '');
    return raw.replace(/\.h$/, '').split('/').pop();
  },

  isDocComment(node) {
    return node.type === 'comment' && node.text.startsWith('/**');
  },

  getDocText(node) {
    return normalizeDescription(node.text);
  },
};

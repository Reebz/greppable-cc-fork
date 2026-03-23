import { normalizeDescription } from '../shared.js';

export default {
  wasmFile: 'tree-sitter-cpp.wasm',
  extensions: ['.cpp', '.hpp', '.cc', '.hh', '.cxx', '.hxx'],
  name: 'cpp',
  langId: 'cpp',

  getExports(node) {
    switch (node.type) {
      case 'function_definition': {
        // Static functions are internal, not exported
        const storageSpecs = node.descendantsOfType('storage_class_specifier');
        if (storageSpecs.some(s => s.text === 'static')) return null;
        // Unwrap: function_definition → declarator → function_declarator → declarator (name)
        let decl = node.childForFieldName('declarator');
        if (decl?.type === 'pointer_declarator') {
          for (let c = 0; c < decl.namedChildCount; c++) {
            if (decl.namedChild(c).type === 'function_declarator') {
              decl = decl.namedChild(c);
              break;
            }
          }
        }
        if (decl?.type === 'function_declarator') {
          const inner = decl.childForFieldName('declarator');
          return inner ? inner.text : null;
        }
        return decl ? decl.text : null;
      }

      case 'class_specifier':
      case 'struct_specifier': {
        const name = node.childForFieldName('name');
        return name ? name.text : null;
      }

      case 'namespace_definition':
        // Namespace is a container, not an export
        return null;

      case 'enum_specifier': {
        const name = node.childForFieldName('name');
        return name ? name.text : null;
      }

      case 'type_definition': {
        // typedef struct { ... } Name; — last type_identifier is the name
        const declarators = node.descendantsOfType('type_identifier');
        const lastDecl = declarators[declarators.length - 1];
        return lastDecl ? lastDecl.text : null;
      }

      default:
        return null;
    }
  },

  getImportModule(node) {
    if (node.type === 'preproc_include') {
      const pathNode = node.childForFieldName('path')
        || node.descendantsOfType('system_lib_string')[0]
        || node.descendantsOfType('string_literal')[0];
      if (!pathNode) return null;
      const raw = pathNode.text.replace(/^[<"]|[>"]$/g, '');
      return raw.replace(/\.h$/, '').replace(/\.hpp$/, '').split('/').pop();
    }

    if (node.type === 'using_declaration') {
      // using namespace std; or using std::string;
      // Extract the namespace identifier
      const idents = node.descendantsOfType('identifier');
      return idents.length > 0 ? idents[0].text : null;
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

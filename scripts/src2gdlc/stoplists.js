/**
 * stoplists.js — Per-language noise filters for CALLS field
 *
 * Symbols in these lists are filtered from @M CALLS to reduce noise.
 * These are common utility functions that appear everywhere and provide
 * no navigational value in a call graph.
 */

/** Shared stoplist — language-agnostic noise */
const shared = new Set([
  'toString', 'valueOf', 'hasOwnProperty',
]);

/** TypeScript / JavaScript stoplist */
export const typescriptStoplist = new Set([
  ...shared,
  'map', 'filter', 'forEach', 'reduce', 'find', 'findIndex', 'some', 'every',
  'flat', 'flatMap', 'sort', 'reverse', 'slice', 'splice', 'concat',
  'push', 'pop', 'shift', 'unshift',
  'keys', 'values', 'entries', 'includes', 'indexOf',
  'join', 'split', 'trim', 'replace', 'match', 'test',
  'parseInt', 'parseFloat', 'isNaN', 'isFinite',
  'JSON', 'parse', 'stringify',
  'console', 'log', 'warn', 'error', 'info', 'debug',
  'setTimeout', 'setInterval', 'clearTimeout', 'clearInterval',
  'Promise', 'resolve', 'reject', 'then', 'catch', 'finally',
  'require',
  'get', 'set', 'delete', 'has', 'clear', 'size',
  'addEventListener', 'removeEventListener',
  'createElement', 'appendChild', 'removeChild',
  'querySelector', 'querySelectorAll', 'getElementById',
]);

/** Python stoplist */
export const pythonStoplist = new Set([
  ...shared,
  'print', 'len', 'range', 'enumerate', 'zip', 'map', 'filter',
  'str', 'int', 'float', 'bool', 'list', 'dict', 'set', 'tuple', 'type',
  'isinstance', 'issubclass', 'hasattr', 'getattr', 'setattr', 'delattr',
  'append', 'extend', 'insert', 'remove', 'pop', 'clear',
  'keys', 'values', 'items', 'get', 'update',
  'join', 'split', 'strip', 'replace', 'format', 'startswith', 'endswith',
  'open', 'read', 'write', 'close',
  'sorted', 'reversed', 'min', 'max', 'sum', 'abs', 'round',
  'super', 'property', 'classmethod', 'staticmethod',
  'next', 'iter',
]);

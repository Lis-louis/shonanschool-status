'use strict';
/** async 関数の本体に、名前つきの引数を渡して実行できる形にする（引数は JSON として埋め込む） */
function wrap(body, args = {}) {
  const names = Object.keys(args).filter(k => /^[A-Za-z_$][\w$]*$/.test(k));
  return `(async ({ ${names.join(', ')} }) => {\n${body}\n})(${JSON.stringify(args)})`;
}
module.exports = { wrap };

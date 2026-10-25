import fs from 'node:fs';
const s = fs.readFileSync('template.html', 'utf8');
const a = s.indexOf('const I=[];'), b = s.indexOf('/* ----------------------------- scenes');
const body = s.slice(a, b).replace(/^function ship[\s\S]*?\n}\n/m, '');
const I = new Function(body.replace('const I=[];', 'const I=[];const PAL={},GR={};') + '\nreturn I;')();
const pre = {A:'a',B:'b',M:'m',S:'s',X:'x',G:'a'};
const out = I.map(o => ({page_id:o.id, art_id: pre[o.f]+'_'+o.id, faction:o.f, cat:o.c, name:o.n, stage:o.st, ground:o.g, gap:o.gap, what:o.w, strong:o.b, weak:o.k}));
fs.writeFileSync('items.json', JSON.stringify(out, null, 1));
console.log(out.length, [...new Set(out.map(o=>o.cat))].map(c=>c+':'+out.filter(o=>o.cat===c).length).join(' '));

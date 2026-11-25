const lp=require('luaparse');const fs=require('fs');
for(const f of process.argv.slice(2)){
  const src=fs.readFileSync(f,'utf8');
  let ast;try{ast=lp.parse(src,{luaVersion:'5.1',scope:true,locations:true})}catch(e){console.log(f,'SYNTAX',e.message);continue}
  const sets=new Set(),gets=new Map();
  (function walk(n){if(!n||typeof n!=='object')return;if(Array.isArray(n)){n.forEach(walk);return}
    if(n.type==='AssignmentStatement')n.variables.forEach(v=>{if(v.type==='Identifier'&&v.isLocal===false)sets.add(v.name)});
    if(n.type==='FunctionDeclaration'&&n.identifier&&n.identifier.type==='Identifier'&&!n.isLocal)sets.add(n.identifier.name);
    if(n.type==='Identifier'&&n.isLocal===false&&!gets.has(n.name))gets.set(n.name,n.loc.start.line);
    for(const k in n)if(k!=='loc')walk(n[k])})(ast.body);
  console.log(f,'OK  globals written:',[...sets].join(', '));
  console.log('   globals read:',[...gets.keys()].sort().join(' '));
}

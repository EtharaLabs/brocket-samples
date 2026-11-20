import {mkdtempSync,mkdirSync,writeFileSync,chmodSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import assert from 'node:assert/strict';
import {check as oracleCheck} from '../../solution/tester/check.mts';
import {check as verifierCheck} from '../grader/check.mts';
import type {Outcome} from '../grader/check.mts';
const root=mkdtempSync(join(tmpdir(),'classification-fixture-'));
const previous=process.env['COMPILER_ROOT'];
const directory=join(root,'fixture/node_modules/.bin');mkdirSync(directory,{recursive:true});
const binary=join(directory,'tsc');
writeFileSync(binary,`#!/usr/bin/env node
import{readFileSync}from'node:fs';
const mode=readFileSync(process.argv.at(-1),'utf8');
switch(mode){
case'accept':process.exit(0);break;
case'reject':console.log('p.ts(1,1): error TS9000: fixture diagnostic');process.exit(2);break;
case'crash':process.exit(3);break;
case'timeout':setInterval(()=>{},1000);break;
default:throw new TypeError('invalid fixture');
}
`);chmodSync(binary,0o755);
process.env['COMPILER_ROOT']=root;
const rows=[];
try{
 for(const expected of ['accept','reject','crash','timeout'] satisfies Outcome[]){
  const started=performance.now();
  const oracle=oracleCheck('fixture',expected),verifier=verifierCheck('fixture',expected);
  assert.equal(oracle,expected);assert.equal(verifier,expected);
  rows.push({expected,oracle,verifier,milliseconds:performance.now()-started});
 }
}finally{
 if(previous===undefined)delete process.env['COMPILER_ROOT'];else process.env['COMPILER_ROOT']=previous;
 rmSync(root,{recursive:true,force:true});
}
console.log(JSON.stringify({platform:process.platform,arch:process.arch,rows}));

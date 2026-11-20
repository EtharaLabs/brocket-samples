import {readFileSync,writeFileSync} from 'node:fs';
import {programs} from '../../solution/tester/generate.mts';
import {arg,pair} from '../../solution/tester/check.mts';
import type {Witness} from '../../solution/tester/check.mts';
import {collect} from './naive_baseline.mts';
const mode:unknown=JSON.parse(readFileSync(new URL('../../mode.json',import.meta.url),'utf8'));
const toolchain=arg('--toolchain');
const seed=Number(arg('--seed','500'));
let witnesses:Witness[]=[];
switch(mode){
 case 'empty':break;
 case 'liar':witnesses=[{id:'fabricated',source:'const x:number=1;',reference:'accept',native:'reject',mechanism:'fabricated'}];break;
 case 'naive':witnesses=collect(toolchain,Number(arg('--budget','300')),seed).witnesses;break;
 case 'spray':{
  for(const p of programs(seed)){
   const [reference,native]=pair(toolchain,p.source);
   if(reference===native)continue;
   for(let i=0;i<4;i++)witnesses.push({...p,id:`${p.id}-${i}`,reference,native,mechanism:'all-type-differences'});
  }
  break;
 }
 default:throw new TypeError('unknown control mode');
}
writeFileSync(arg('--out'),JSON.stringify({witnesses})+'\n');

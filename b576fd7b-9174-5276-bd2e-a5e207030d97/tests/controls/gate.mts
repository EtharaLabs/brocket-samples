import {readFileSync,writeFileSync} from 'node:fs';
import {collect} from './naive_baseline.mts';
import {pair,arg} from '../grader/check.mts';
const windows: {id:string;pre:string;post:string}[]=JSON.parse(readFileSync(new URL('../grader/windows.json',import.meta.url),'utf8'));
const rows=[];
for(const w of windows) {
 const result=collect(w.pre,300,500);
 const flips=result.witnesses.filter(p=>{const after=pair(w.post,p.source);return after[0]===after[1];});
 rows.push({window:w.id,pre:w.pre,post:w.post,tried:result.tried,splits:result.witnesses.length,flips:flips.length,milliseconds:result.milliseconds,witnesses:flips});
 writeFileSync(arg('--out'),JSON.stringify({platform:process.platform,arch:process.arch,budget:300,workers:1,seed:500,rows},null,2)+'\n');
 console.log(JSON.stringify(rows.at(-1)));
}

import {readFileSync,writeFileSync} from 'node:fs';
import {programs} from '../../solution/tester/generate.mts';
import {arg,pair} from '../grader/check.mts';
const windows:{id:string;pre:string;post:string}[]=JSON.parse(readFileSync(new URL('../grader/windows.json',import.meta.url),'utf8'));
const candidates=[...programs()];
const rows=[];
for(const w of windows){
 const measurements=candidates.map(p=>({...p,before:pair(w.pre,p.source),after:pair(w.post,p.source)}));
 const credited=measurements.filter(p=>p.before[0]!==p.before[1]&&p.after[0]===p.after[1]);
 rows.push({...w,credited:credited.map(p=>({id:p.id,mechanism:p.mechanism,bytes:Buffer.byteLength(p.source),before:p.before,after:p.after})),measurements});
 writeFileSync(arg('--out'),JSON.stringify({platform:process.platform,arch:process.arch,rows},null,2)+'\n');
}
const development=candidates.map(p=>({...p,outcomes:pair('dev',p.source)}));
writeFileSync(arg('--out'),JSON.stringify({platform:process.platform,arch:process.arch,rows,development,development_splits:development.filter(p=>p.outcomes[0]!==p.outcomes[1]).length},null,2)+'\n');

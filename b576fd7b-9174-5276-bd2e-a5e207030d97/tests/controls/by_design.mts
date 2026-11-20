import {readFileSync,writeFileSync} from 'node:fs';
import {pair,arg} from '../grader/check.mts';
const source='type Ref<T>=T|{value:T};declare function f<D=string>(o:{select?:Ref<(x:string)=>D>}):D|undefined;declare const arg:{select?:Ref<(x:string)=>string>}&{select:(x:string)=>number};const n:number|undefined=f(arg);';
const windows:{id:string;pre:string;post:string}[]=JSON.parse(readFileSync(new URL('../grader/windows.json',import.meta.url),'utf8'));
const rows=windows.map(w=>{const before=pair(w.pre,source),after=pair(w.post,source);return {...w,before,after,credited:before[0]!==before[1]&&after[0]===after[1]};});
writeFileSync(arg('--out'),JSON.stringify({issue:'microsoft/typescript-go#4817',reason:'Documented stable type ordering; not a corrected port divergence',source,rows,total_credited:rows.filter(r=>r.credited).length},null,2)+'\n');

import {programs} from '../../solution/tester/generate.mts';
import {arg,pair} from '../grader/check.mts';
import {writeFileSync} from 'node:fs';
const toolchain=arg('--toolchain');
const rows=[...programs(Number(arg('--seed','0')))].map(p=>({...p,outcomes:pair(toolchain,p.source)}));
writeFileSync(arg('--out'),JSON.stringify({toolchain,platform:process.platform,arch:process.arch,rows},null,2)+'\n');

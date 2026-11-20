import {mkdtempSync,writeFileSync,rmSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
export type Outcome='accept'|'reject'|'crash'|'timeout';
export type Witness={readonly id:string;readonly source:string;readonly reference:Outcome;readonly native:Outcome;readonly mechanism:string};
export const flags=['--noEmit','--strict','--target','es2022','--module','esnext','--moduleResolution','bundler','--lib','es2022','--pretty','false'] as const;
export function check(version:string,source:string):Outcome {
 const dir=mkdtempSync(join(tmpdir(),'verify-check-'));
 try {
  writeFileSync(join(dir,'p.ts'),source);
  const result=spawnSync(join(process.env['COMPILER_ROOT']??'/opt/compilers',version,'node_modules/.bin/tsc'),[...flags,join(dir,'p.ts')],{
   cwd:dir,encoding:'utf8',timeout:60000,killSignal:'SIGKILL',maxBuffer:8*1024*1024,
   env:{PATH:process.env['PATH'],HOME:dir,GOMAXPROCS:'2',LANG:'C.UTF-8'},
  });
  if(result.error&&'code'in result.error&&result.error.code==='ETIMEDOUT')return 'timeout';
  if(result.error&&'code'in result.error&&result.error.code==='ENOENT')throw result.error;
  if(result.status===0)return 'accept';
  return (result.status===1||result.status===2)&&/\berror TS\d+:/.test((result.stdout??'')+(result.stderr??''))?'reject':'crash';
 }finally{rmSync(dir,{recursive:true,force:true});}
}
export function pair(version:string,source:string):readonly [Outcome,Outcome]{return [check('reference',source),check(version,source)];}
export function arg(name:string,fallback?:string):string{
 const i=process.argv.indexOf(name);const v=i<0?fallback:process.argv[i+1];
 if(v===undefined)throw new TypeError(`Missing ${name}`);return v;
}

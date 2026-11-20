// FORGE-CANARY-BEGIN
// FORGE-CANARY-SLOT-1: 3ddccc53ce11e5863c8da9b31e5ecf88a88aa81c5837517c50653000cf9c4deb
// FORGE-CANARY-SLOT-2: 9fd86250d3b787176068cbad3642f5444dbb5a1ae12fab88129041a8fbecc900
// FORGE-CANARY-SLOT-3: 0806122145c059db2a8c1cf847aed5b7954cafc1ea5184bed48b2294293eb661
// FORGE-CANARY-END
import {mkdtempSync, writeFileSync, rmSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {join} from 'node:path';

export type Outcome = 'accept' | 'reject' | 'crash' | 'timeout';
export type Witness = {readonly id:string; readonly source:string; readonly reference:Outcome; readonly native:Outcome; readonly mechanism:string};
export const flags = ['--noEmit','--strict','--target','es2022','--module','esnext','--moduleResolution','bundler','--lib','es2022','--pretty','false'] as const;
export function check(version:string, source:string):Outcome {
  const dir=mkdtempSync(join(tmpdir(),'checker-'));
  try {
    writeFileSync(join(dir,'p.ts'),source);
    const root=process.env['COMPILER_ROOT']??'/opt/compilers';
    const result=spawnSync(join(root,version,'node_modules/.bin/tsc'),[...flags,join(dir,'p.ts')],{
      cwd:dir,encoding:'utf8',timeout:60000,killSignal:'SIGKILL',maxBuffer:8*1024*1024,
      env:{PATH:process.env['PATH'],HOME:dir,GOMAXPROCS:'2',LANG:'C.UTF-8'},
    });
    if(result.error && 'code' in result.error && result.error.code==='ETIMEDOUT') return 'timeout';
    if(result.error && 'code' in result.error && result.error.code==='ENOENT') throw result.error;
    if(result.status===0)return 'accept';
    return (result.status===1||result.status===2)&&/\berror TS\d+:/.test((result.stdout??'')+(result.stderr??''))?'reject':'crash';
  } finally {rmSync(dir,{recursive:true,force:true});}
}
export function pair(version:string,source:string):readonly [Outcome,Outcome] {
  return pairWith(version,source,false);
}
// identical=true checks the SAME compiler on both sides, so no program can split.
export function pairWith(version:string,source:string,identical:boolean):readonly [Outcome,Outcome] {
  return [check(identical?version:'reference',source),check(version,source)];
}
export function arg(name:string,fallback?:string):string {
  const i=process.argv.indexOf(name);const value=i<0?fallback:process.argv[i+1];
  if(value===undefined)throw new TypeError(`Missing ${name}`);
  return value;
}

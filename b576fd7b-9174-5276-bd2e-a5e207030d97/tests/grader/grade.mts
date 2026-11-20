import {accessSync,constants,existsSync,readFileSync,writeFileSync,mkdirSync,mkdtempSync,chmodSync,rmSync,statSync,readdirSync} from 'node:fs';
import {join,dirname,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {spawn} from 'node:child_process';
import {arg,pair} from './check.mts';
import type {Witness,Outcome} from './check.mts';

type Window={readonly id:string;readonly pre:string;readonly post:string;readonly mechanism:string};
const windowsArg=process.argv.includes('--windows')?process.argv[process.argv.indexOf('--windows')+1]:undefined;
const windows:Window[]=JSON.parse(readFileSync(windowsArg??new URL('./windows.json',import.meta.url),'utf8'));
const CAP=200,ALLOWANCE=3,MINIMAL_BYTES=3200,RECHECKS=2;
const tester=resolve(arg('--tester','/app/tester/run'));
const budget=Number(arg('--budget','300')),seed=arg('--seed','20261113');
const out=arg('--out','/logs/verifier/reward.json');
if(!Number.isFinite(budget)||budget<130)throw new RangeError('budget must leave room for two 60s checks');

function outcome(value:unknown):value is Outcome{return value==='accept'||value==='reject'||value==='crash'||value==='timeout';}
function object(value:unknown):value is Record<string,unknown>{return typeof value==='object'&&value!==null&&!Array.isArray(value);}
// A malformed witness is dropped and counted, never fatal: one bad row among many good ones costs
// its own credit and the precision allowance it consumed, and the report still grades. Only a
// report that is not a report at all, or that breaks the declared size bound, is unreadable.
type Report={readonly witnesses:Witness[];readonly malformed:number;readonly unreadable:string|null};
function readReport(path:string):Report{
 if(statSync(path).size>2*1024*1024)return {witnesses:[],malformed:0,unreadable:'report exceeds 2MiB'};
 let parsed:unknown;
 try{parsed=JSON.parse(readFileSync(path,'utf8'));}
 catch(error){return {witnesses:[],malformed:0,unreadable:error instanceof Error?error.message:'unparseable report'};}
 if(!object(parsed)||!Array.isArray(parsed['witnesses']))return {witnesses:[],malformed:0,unreadable:'expected witnesses array'};
 const witnesses:Witness[]=[];const ids=new Set<string>();let malformed=0;
 for(const w of parsed['witnesses'].slice(0,CAP)){
  if(!object(w)||typeof w['id']!=='string'||typeof w['source']!=='string'||typeof w['mechanism']!=='string'||!outcome(w['reference'])||!outcome(w['native'])){malformed++;continue;}
  if(ids.has(w['id'])||!w['id']||!w['mechanism'].trim()||Buffer.byteLength(w['source'])>65536){malformed++;continue;}
  ids.add(w['id']);
  witnesses.push({id:w['id'],source:w['source'],mechanism:w['mechanism'],reference:w['reference'],native:w['native']});
 }
 return {witnesses,malformed,unreadable:null};
}
// An outcome class is stable only when repeated measurement agrees. A class that moves between
// repeats is this verifier's own timing noise, never the agent's claim, so it is recorded as
// unstable and charged to nobody.
function stablePair(version:string,source:string):{pair:readonly [Outcome,Outcome]|null;unstable:boolean}{
 const first=pair(version,source);
 if(!first.includes('timeout'))return {pair:first,unstable:false};
 for(let attempt=0;attempt<RECHECKS;attempt++){
  const again=pair(version,source);
  if(again[0]===first[0]&&again[1]===first[1])return {pair:first,unstable:false};
 }
 return {pair:null,unstable:true};
}
// Strip comments before scanning, so documenting the environment in prose is not an offence. String
// literals stay in scope deliberately: a version-to-input table is built from version strings, and
// the red line forbids exactly that. So a comment naming a version is clean and a version living in
// code, quoted or not, still fires. The scan stays a partial control either way: it reads no file at
// or above a mebibyte and sees through no obfuscation.
function executable(source:string):string{
 return source.replace(/\/\*[\s\S]*?\*\//g,' ').replace(/(^|[^:])\/\/[^\n]*/g,'$1 ');
}
function hardcoded(path:string):boolean{
 for(const entry of readdirSync(path,{withFileTypes:true})){
  if(entry.isSymbolicLink())continue;
  const p=join(path,entry.name);
  if(entry.isDirectory()&&entry.name!=='node_modules'&&hardcoded(p))return true;
  if(entry.isFile()&&/\.(mts|ts|js|mjs)$|^run$/.test(entry.name)&&statSync(p).size<1024*1024){
   if(/\b7\.[0-9]+\.[0-9]+(?:-dev\.[0-9]+\.[0-9]+)?\b/.test(executable(readFileSync(p,'utf8'))))return true;
  }
 }
 return false;
}
async function launch(toolchain:string,report:string):Promise<string>{
 return new Promise(resolveLaunch=>{
  const child=spawn(tester,['--toolchain',toolchain,'--budget',String(budget),'--seed',seed,'--out',report],{
   cwd:dirname(tester),detached:true,uid:65534,gid:65534,stdio:'ignore',
   env:{PATH:'/usr/local/bin:/usr/bin:/bin',HOME:dirname(report),LANG:'C.UTF-8',GOMAXPROCS:'2',COMPILER_ROOT:process.env['COMPILER_ROOT']??'/opt/compilers'},
  });
  let timedOut=false;
  const timer=setTimeout(()=>{timedOut=true;if(child.pid)process.kill(-child.pid,'SIGKILL');},budget*1100);
  child.on('error',()=>{clearTimeout(timer);resolveLaunch('launch-failed');});
  child.on('close',code=>{clearTimeout(timer);resolveLaunch(timedOut?'timeout':code===0?'ok':'exit-failed');});
 });
}
type Row={readonly window:string;readonly ran:string;readonly shown:number;readonly invalid:number;readonly fabricated:number;readonly malformed:number;readonly unstable:number;readonly unreadable:string|null;readonly background:number;readonly credited:number;readonly minimal:number;readonly labels:readonly string[];readonly precision:number;readonly milliseconds:number};
const rows:Row[]=[];let note='';let setupValid=true;let infrastructure:string|null=null;
try{accessSync(tester,constants.X_OK);if(hardcoded(dirname(tester))){note='version-specific literals in tester';setupValid=false;}}
catch(error){if(!(error instanceof Error))throw error;note=`missing executable entry point: ${tester}`;setupValid=false;}
const scratch=mkdtempSync(join(tmpdir(),'grade-checker-'));chmodSync(scratch,0o777);
try{
 if(setupValid)for(const w of windows){
  const started=performance.now();const report=join(scratch,`${w.id}.json`);
  const ran=await launch(w.pre,report);
  let witnesses:Witness[]=[];let fabricated=0,malformed=0,unstable=0,background=0,credited=0,minimal=0;const labels:string[]=[];
  let unreadable:string|null=null;
  // A report on disk is graded whichever way the process exited: bytes already written are
  // evidence, and a non-zero exit costs its own factor rather than discarding the work.
  if(existsSync(report)){
   const read=readReport(report);
   witnesses=read.witnesses;malformed=read.malformed;unreadable=read.unreadable;
   if(unreadable)note=unreadable;
  }else if(ran==='ok'){unreadable='the tester exited 0 and wrote no report';note=unreadable;}
  for(const p of witnesses){
   const before=stablePair(w.pre,p.source);
   if(before.unstable){unstable++;continue;}
   const observed=before.pair as readonly [Outcome,Outcome];
   if(observed[0]===observed[1]||observed[0]!==p.reference||observed[1]!==p.native){fabricated++;continue;}
   const after=stablePair(w.post,p.source);
   if(after.unstable){unstable++;continue;}
   const settled=after.pair as readonly [Outcome,Outcome];
   if(settled[0]!==settled[1]){background++;continue;}
   credited++;minimal+=Number(Buffer.byteLength(p.source)<=MINIMAL_BYTES);labels.push(p.mechanism.trim().toLowerCase().replace(/\s+/g,' '));
  }
  const shown=witnesses.length+malformed;
  rows.push({window:w.id,ran,shown,invalid:fabricated,fabricated,malformed,unstable,unreadable,background,credited,minimal,labels,precision:Math.min(1,ALLOWANCE/Math.max(1,shown)),milliseconds:performance.now()-started});
 }
}catch(error){
 // The verifier's own toolchains are infrastructure. A missing or unrunnable compiler installation
 // is this image's fault, never the submission's, so it is reported as such and never as a zero
 // the agent earned. instruction.md states the same rule for the agent's own tester.
 infrastructure=error instanceof Error?`${error.message}`:'infrastructure error';
 note=`infrastructure error, not an agent finding: ${infrastructure}`;
}finally{rmSync(scratch,{recursive:true,force:true});}
const caught=rows.filter(r=>r.credited>0);
const fabricated=rows.reduce((s,r)=>s+r.fabricated,0);
const malformed=rows.reduce((s,r)=>s+r.malformed,0);
const unstable=rows.reduce((s,r)=>s+r.unstable,0);
const unreadable=rows.filter(r=>r.unreadable!==null).length;
const invalid=fabricated;
// The gate asks one question: did the submission claim a finding this verifier could not reproduce.
// It no longer conflates that with the verifier's own timing noise, with an infrastructure fault of
// this image, with a malformed row among sound ones, or with the exit status of a process whose
// report is already on disk. Each of those is carried in its own field and costs its own factor.
const launched=rows.length===windows.length&&rows.every(r=>r.ran!=='launch-failed');
const validity_gate=Number(infrastructure===null&&setupValid&&fabricated===0&&unreadable===0&&launched);
const recall=caught.length/windows.length;
// An invocation that exited non-zero or overran its budget still had its report graded, and pays
// here instead of at the gate. A clean exit on every window leaves this factor at one.
const completion=rows.length?rows.filter(r=>r.ran==='ok').length/rows.length:0;
const precision=rows.reduce((s,r)=>s+r.precision,0)/windows.length;
const attributed=caught.filter(r=>new Set(r.labels).size===1&&!caught.some(o=>o.window!==r.window&&o.labels.some(l=>r.labels.includes(l)))).length;
const attribution=caught.length?attributed/caught.length:0;
const credited=rows.reduce((s,r)=>s+r.credited,0);
const minimality=credited?rows.reduce((s,r)=>s+r.minimal,0)/credited:0;
const result={reward:validity_gate*recall*precision*attribution*minimality*completion,validity_gate,recall,precision,attribution,minimality,completion,caught:caught.length,graded:windows.length,invalid,fabricated,malformed,unstable,unreadable,infrastructure_error:infrastructure===null?0:1,credited,witnesses_read:rows.reduce((s,r)=>s+r.shown,0),note,infrastructure,rows,platform:process.platform,arch:process.arch};
mkdirSync(dirname(out),{recursive:true});
writeFileSync(out,JSON.stringify(Object.fromEntries(Object.entries(result).filter(([,v])=>typeof v==='number')),null,2)+'\n');
writeFileSync(join(dirname(out),'report.json'),JSON.stringify(result,null,2)+'\n');
writeFileSync(join(dirname(out),'reward.txt'),`${result.reward}\n`);
const checks={witnesses_reproduce:fabricated===0&&setupValid,post_fix_agreement_required:caught.every(r=>r.credited>0),witness_cap_enforced:rows.every(r=>r.shown<=CAP),tester_launched:launched,report_readable:unreadable===0,both_checker_modes_named:rows.every(r=>r.fabricated===0)&&setupValid,version_independent:setupValid,no_infrastructure_error:infrastructure===null,outcomes_stable:unstable===0};
const tests=Object.entries(checks).map(([name,ok])=>({name,status:ok?'passed':'failed',duration:0}));
writeFileSync(join(dirname(out),'ctrf.json'),JSON.stringify({results:{tool:{name:'typescript-checker-differential'},summary:{tests:tests.length,passed:tests.filter(t=>t.status==='passed').length,failed:tests.filter(t=>t.status==='failed').length,pending:0,skipped:0,other:0},tests}},null,2)+'\n');
const structured={valid:Boolean(validity_gate),score:result.reward,pass_rate:result.reward,total_tests:tests.length,passed:tests.filter(t=>t.status==='passed').length,failed:tests.filter(t=>t.status==='failed').length,errors:validity_gate?0:1,summary:`reward ${result.reward.toFixed(4)}: gate ${validity_gate}, caught ${caught.length} of ${windows.length}, precision ${precision.toFixed(4)}, attribution ${attribution.toFixed(4)}, minimality ${minimality.toFixed(4)}, completion ${completion.toFixed(4)}${infrastructure?`, INFRASTRUCTURE ERROR: ${infrastructure}`:''}${unstable?`, ${unstable} unstable recheck(s) charged to nobody`:''}`,details:tests.map(t=>({name:t.name,status:t.status,score:t.status==='passed'?1:0,message:note})),metrics:{reward:result.reward,validity_gate,recall,precision,attribution,minimality,completion,caught:caught.length,graded:windows.length,invalid,fabricated,malformed,unstable,unreadable,infrastructure_error:infrastructure===null?0:1,credited,witnesses_read:result.witnesses_read}};
console.log(JSON.stringify(result));
// The structured_json parser task.toml declares reads this block and nothing else on stdout.
console.log('>>>>> Start Structured Result');
console.log(JSON.stringify(structured));
console.log('>>>>> End Structured Result');

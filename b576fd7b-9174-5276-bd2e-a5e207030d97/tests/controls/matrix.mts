import {cpSync,mkdirSync,rmSync,writeFileSync,readFileSync,chmodSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
const rows=[];
for(const mode of ['oracle','missing','empty','naive','spray','liar','impossible','mode-discipline','one-mechanism']){
 rmSync('/app/tester',{recursive:true,force:true});mkdirSync('/app/tester',{recursive:true});
 if(mode==='oracle'){
  cpSync('/root/oracle/tester','/app/tester',{recursive:true});chmodSync('/app/tester/run',0o755);
 }else if(mode==='mode-discipline'||mode==='one-mechanism'){
  // The real oracle, handicapped by one CLI argument, must score below the pass bar.
  cpSync('/root/oracle/tester','/app/tester',{recursive:true});
  const handicap=mode==='mode-discipline'?'--modes same':'--family union-matching-depth';
  writeFileSync('/app/tester/run',`#!/bin/sh\nexec node "$(dirname "$0")/main.mts" ${handicap} "$@"\n`);
  chmodSync('/app/tester/run',0o755);
 }else if(mode!=='missing'){
  mkdirSync('/app/tester/tests/controls',{recursive:true});mkdirSync('/app/tester/tests/grader');mkdirSync('/app/tester/solution/tester',{recursive:true});
  for(const file of ['generate.mts','check.mts'])cpSync('/root/oracle/tester/'+file,'/app/tester/solution/tester/'+file);
  cpSync('/tests/grader/check.mts','/app/tester/tests/grader/check.mts');
  for(const file of ['submission.mts','naive_baseline.mts'])cpSync('/tests/controls/'+file,'/app/tester/tests/controls/'+file);
   writeFileSync('/app/tester/mode.json',JSON.stringify(mode==='impossible'?'spray':mode));
  writeFileSync('/app/tester/run',"#!/usr/bin/env node\nimport './tests/controls/submission.mts';\n");chmodSync('/app/tester/run',0o755);
 }
 const logdir='/evidence/matrix/'+mode;mkdirSync(logdir,{recursive:true});
 const started=performance.now();
  const graderArgs=['/tests/grader/grade.mts','--tester','/app/tester/run','--budget','300','--seed','20261113','--out',logdir+'/reward.json'];
  if(mode==='impossible')graderArgs.push('--windows','/tests/grader/impossible-window.json');
  const run=spawnSync('node',graderArgs,{encoding:'utf8',timeout:3000000,killSignal:'SIGKILL',maxBuffer:8*1024*1024});
 writeFileSync(logdir+'/stdout.log',run.stdout??'');writeFileSync(logdir+'/stderr.log',run.stderr??'');
 if(run.status!==0)throw new TypeError(`grader failed in ${mode}: ${run.stderr}`);
 const result:Record<string,unknown>=JSON.parse(readFileSync(logdir+'/report.json','utf8'));
 rows.push({submission:mode,milliseconds:performance.now()-started,...result});
 writeFileSync('/evidence/validation-matrix.json',JSON.stringify({platform:process.platform,arch:process.arch,node:process.version,rows},null,2)+'\n');
 console.log(JSON.stringify({submission:mode,...result}));
}

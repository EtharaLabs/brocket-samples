// FORGE-CANARY-BEGIN
// FORGE-CANARY-SLOT-1: 3ddccc53ce11e5863c8da9b31e5ecf88a88aa81c5837517c50653000cf9c4deb
// FORGE-CANARY-SLOT-2: 9fd86250d3b787176068cbad3642f5444dbb5a1ae12fab88129041a8fbecc900
// FORGE-CANARY-SLOT-3: 0806122145c059db2a8c1cf847aed5b7954cafc1ea5184bed48b2294293eb661
// FORGE-CANARY-END
import {writeFileSync} from 'node:fs';
import {arg,pair,pairWith} from './check.mts';
import type {Witness} from './check.mts';
import {programs} from './generate.mts';

const toolchain=arg('--toolchain');
if(!/^(dev|[0-9A-Za-z][0-9A-Za-z.+-]*)$/.test(toolchain))throw new TypeError('Invalid toolchain name');
const budget=Number(arg('--budget','300'));
const seed=Number(arg('--seed','0'));
const out=arg('--out');
const identicalModes=arg('--modes','pair')==='same';
const family=arg('--family','all');
const started=performance.now();
const witnesses:Witness[]=[];
const seen=new Set<string>();
// Check potentially expensive cyclic graphs first, while the full timeout reserve remains.
const candidates=[...programs(seed)].sort((a,b)=>Number(b.id.startsWith('ring-'))-Number(a.id.startsWith('ring-')));
for(const candidate of candidates) {
  if(witnesses.length===3)break;
  if(performance.now()-started>budget*1000-125000)break;
  if(seen.has(candidate.mechanism))continue;
  if(family!=='all'&&candidate.mechanism!==family)continue;
  const [reference,native]=pairWith(toolchain,candidate.source,identicalModes);
  if(reference===native)continue;
  // The public development compiler is a neutral control, not an inventory of hidden versions.
  const control=pair('dev',candidate.source);
  if(control[0]!==control[1])continue;
  const repeat=pair(toolchain,candidate.source);
  if(repeat[0]!==reference||repeat[1]!==native)continue;
  witnesses.push({...candidate,reference,native});seen.add(candidate.mechanism);
}
writeFileSync(out,JSON.stringify({witnesses},null,2)+'\n');

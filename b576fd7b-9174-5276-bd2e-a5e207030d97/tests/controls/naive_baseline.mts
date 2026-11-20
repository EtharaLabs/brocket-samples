import {writeFileSync} from 'node:fs';
import {arg,pair} from '../grader/check.mts';
import type {Witness} from '../grader/check.mts';

// Independent production sampling. The grammar covers every construct used by the oracle,
// but carries no dependency graph, variance model, re-entrant call model, or binding correlation.
export function* naivePrograms(seed=500,count=512):Generator<string> {
  let state=seed>>>0;
  const pick=(choices:readonly string[]):string=>{state=(Math.imul(state,1664525)+1013904223)>>>0;return choices[(state>>>8)%choices.length]??'number';};
  for(let i=0;i<count;i++) {
    const leaf=pick(['number','string','boolean','unknown']);
    const wrapper=pick(['T','T[]','readonly T[]','T|undefined','{value:T}','Required<T>','Readonly<T>']);
    const property=pick(['value','payload','key','status']);
    const members=pick([`value:${wrapper}`,`method:(x:T)=>${wrapper}`,`value?:${wrapper}`,`method:<U>(x:U)=>T`]);
    const base=pick(['','extends A<T>']);
    const mapped=pick(['keyof T','keyof T & string',"Exclude<keyof T,'key'>"]);
    const remap=pick(['K',"K extends 'key'?never:K"]);
    const flow=pick(["const {status,payload}=s;if(status==='ready')payload;",'assert(true);','if(s.status) s.payload;']);
    yield pick([
      `interface A<T>{${members}}interface B<T> ${base}{extra?:${wrapper}}interface C<T> extends B<T>{}declare const b:B<${leaf}>;const a:A<${leaf}>=b;`,
      `type M<T>={[K in ${mapped} as ${remap}]:T[K]};declare const m:M<{a:${leaf};key:number}>;m;`,
      `type Indexed<T,K extends keyof T>=T[K];type I=Indexed<{${property}:${leaf}},'${property}'>;`,
      `type Union<T>=T|{value:T};declare function call<T>(x:Union<T>,y?:T[]):T;declare const value:${leaf};call(value);`,
      `class Entity{private secret=1;protected hidden=2}class Account extends Entity{field=''}declare function get<T extends object=object>():Readonly<Account&T>;const item=get<object>();`,
      `type State={status:'ready';payload:${leaf}}|{status:'pending';payload?:undefined};declare const s:State;declare function assert(c:boolean):asserts c;declare function assert(c:boolean,m:string):asserts c;${flow}`,
      `interface Node<T>{value:${wrapper};next?:Node<T>[]}declare const a:Node<${leaf}>;const b:Node<${leaf}>=a;export {};`,
      `type Conditional<T>=T extends string?${leaf}:never;declare const a:Conditional<string>;a;`,
      `type F=(x?:{${property}?:${leaf}})=>void;const f:F=({${property}}={})=>{${property};};`,
    ]);
  }
}
export function collect(toolchain:string,budget:number,seed:number) {
  const start=performance.now();const witnesses:Witness[]=[];let tried=0;
  for(const source of naivePrograms(seed)) {
    if(performance.now()-start>budget*1000-125000)break;
    const [reference,native]=pair(toolchain,source);tried++;
    if(reference!==native)witnesses.push({id:`naive-${tried}`,source,reference,native,mechanism:'independent-syntax'});
  }
  return {witnesses,tried,milliseconds:performance.now()-start};
}
if(import.meta.url===`file://${process.argv[1]}`) {
  writeFileSync(arg('--out'),JSON.stringify(collect(arg('--toolchain'),Number(arg('--budget','300')),Number(arg('--seed','500'))),null,2)+'\n');
}

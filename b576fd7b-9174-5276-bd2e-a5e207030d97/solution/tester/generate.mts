// FORGE-CANARY-BEGIN
// FORGE-CANARY-SLOT-1: 3ddccc53ce11e5863c8da9b31e5ecf88a88aa81c5837517c50653000cf9c4deb
// FORGE-CANARY-SLOT-2: 9fd86250d3b787176068cbad3642f5444dbb5a1ae12fab88129041a8fbecc900
// FORGE-CANARY-SLOT-3: 0806122145c059db2a8c1cf847aed5b7954cafc1ea5184bed48b2294293eb661
// FORGE-CANARY-END
export type Program={readonly id:string;readonly mechanism:string;readonly source:string};
// Structural families: vary graph size, key constraints, leaf types, and declaration roles.
// No version inspection, bug identifiers, diagnostics, or upstream test file names.
export function* programs(seed=0):Generator<Program> {
  const suffix=Math.abs(seed%997);
  for(const leaf of ['number','string']) {
    yield {id:`depth-${leaf}`,mechanism:'union-matching-depth',source:`interface Column<T>{dataIndex?:(T|(string&{}))[]} declare function table<T>(rows:readonly T[],columns:Column<T>[]):void;declare const rows:{id:${leaf}}[];table(rows,[{dataIndex:['id']}]);`};
    yield {id:`flow-${leaf}`,mechanism:'dependent-binding-reentrance',source:`type State={status:'ready';payload:{value?:${leaf}}}|{status:'pending';payload?:undefined};declare function state():State;declare function assert(c:boolean):asserts c;declare function assert(c:boolean,m:string):asserts c;const read=()=>{const {status,payload}=state();if(status!=='ready')throw new Error();assert(payload.value!==undefined);return payload.value};`};
    yield {id:`key-${leaf}`,mechanism:'remapped-key-constraint',source:`type Filter${suffix}<T>={[K in keyof T & string as K extends '_key'?never:K]:${leaf}}[Exclude<keyof T & string,'_key'>];`};
    yield {id:`private-${leaf}`,mechanism:'reverse-mapping-accessibility',source:`class Entity{private secret=1;protected hidden=2;mark(field:string):void{}}class Account extends Entity{email=''}declare function get<T extends object=object>():Readonly<Account&T>;const inferred=get() as Account;`};
    yield {id:`inherit-${leaf}`,mechanism:'inherited-variance-layout',source:`interface A<T>{inherited:()=>T}interface B<T> extends A<T>{own:(x:T)=>Required<T>}interface C<T> extends B<T>{}declare const narrow:C<{a:${leaf}}>;const wide:C<{a:${leaf};b?:number}>=narrow;`};
  }
  for(const size of [34,36,40]) {
    const declarations=Array.from({length:size},(_,i)=>`interface A${i}{v:string;n?:A${(i+1)%size}[]}interface B${i}{v:string;n?:B${(i+1)%size}[]}`).join('\n');
    yield {id:`ring-${size}`,mechanism:'array-linked-relation-cycle',source:`${declarations}\ndeclare const a:A0;const b:B0=a;`};
  }
}

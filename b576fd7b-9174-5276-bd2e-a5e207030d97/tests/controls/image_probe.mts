import{readFileSync,readdirSync,existsSync}from'node:fs';
import{createHash}from'node:crypto';
import{spawnSync}from'node:child_process';
const root='/opt/compilers';
const compilers=readdirSync(root).sort().map(name=>{
 const metadata:{version:string}=JSON.parse(readFileSync(`${root}/${name}/node_modules/typescript/package.json`,'utf8'));
 const binary=spawnSync(`${root}/${name}/node_modules/.bin/tsc`,['--version'],{encoding:'utf8',timeout:60000});
 return {name,package_version:metadata.version,status:binary.status,version_output:binary.stdout.trim()};
});
const hashes=Object.fromEntries(['/tests/grader/grade.mts','/tests/grader/check.mts','/tests/grader/windows.json','/tests/test.sh'].filter(existsSync).map(path=>[path,createHash('sha256').update(readFileSync(path)).digest('hex')]));
console.log(JSON.stringify({node:process.version,platform:process.platform,arch:process.arch,compilers,hashes},null,2));

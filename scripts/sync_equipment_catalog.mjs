import {readFile, writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {dirname, resolve} from 'node:path';

const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const catalog=JSON.parse(await readFile(resolve(root,'game/data/equipment_catalog.json'),'utf8'));
if(catalog.version!==1)throw new Error('Unsupported equipment catalog version');
const begin='// BEGIN GENERATED EQUIPMENT CATALOG';
const end='// END GENERATED EQUIPMENT CATALOG';
const target=resolve(root,'web/meta.js');
const source=await readFile(target,'utf8');
const generated=`${begin}\n// Source: game/data/equipment_catalog.json. Run node scripts/sync_equipment_catalog.mjs.\nexport const CATALOG = ${JSON.stringify(catalog)};\n${end}`;
const next=source.includes(begin)?source.replace(new RegExp(`${begin}[\\s\\S]*?${end}`),generated):generated+'\n'+source;
if(process.argv.includes('--check')){
  if(next!==source)throw new Error('Web equipment catalog is stale; run node scripts/sync_equipment_catalog.mjs');
  console.log('Shared equipment catalog is synchronized.');
}else if(next!==source){
  await writeFile(target,next);
  console.log('Shared equipment catalog generated in web/meta.js.');
}

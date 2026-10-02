import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';

const root = path.resolve(import.meta.dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const walk = dir => fs.readdirSync(path.join(root, dir), { withFileTypes: true }).flatMap(entry => entry.isDirectory() ? walk(`${dir}/${entry.name}`) : [`${dir}/${entry.name}`]);
const project = read('SnowOps.xcodeproj/project.pbxproj');
const definitions = new Set([...project.matchAll(/^([A-F0-9]{24}) = \{/gm)].map(match => match[1]));
const references = [...project.matchAll(/\b[A-F0-9]{24}\b/g)].map(match => match[0]);
for (const reference of references) assert(definitions.has(reference), `Undefined project reference: ${reference}`);
const paths = [...project.matchAll(/lastKnownFileType = sourcecode.swift; path = "([^"]+)"/g)].map(match => match[1]);
for (const file of paths) assert(fs.existsSync(path.join(root, file)), `Missing source file: ${file}`);
const allSources = [...walk('SnowOps'), ...walk('SnowOpsTests')].filter(file => file.endsWith('.swift'));
assert.equal(paths.length, allSources.length, 'Project omits or duplicates application/test sources');
for (const file of allSources) assert(paths.includes(file), `Source omitted: ${file}`);
for (const file of [...allSources, ...walk('Sources'), ...walk('Tests')].filter(file => file.endsWith('.swift'))) {
  const source = read(file);
  assert(source.trim().length > 0, `Empty source: ${file}`);
  assert(!source.includes('fatalError('), `Unrecoverable error path: ${file}`);
}
assert(read('SnowOps/Features/Map/OperationsMapView.swift').includes('.glassEffect('));
assert(read('SnowOps/Persistence/LocalRepository.swift').includes('.atomic'));
assert(read('SnowOps/App/OperationsStore.swift').includes('beforeState.audit = []'));
const scheme = read('SnowOps.xcodeproj/xcshareddata/xcschemes/SnowOps.xcscheme');
for (const match of scheme.matchAll(/BlueprintIdentifier="([A-F0-9]{24})"/g)) assert(definitions.has(match[1]));
const testCount = [...walk('Tests'), ...walk('SnowOpsTests')].reduce((total, file) => total + (read(file).match(/func test\w+/g) ?? []).length, 0);
console.log(`PASS: ${paths.length} project source references, ${definitions.size} project objects, shared scheme and required persistence/glass source checks.`);
console.log(`Found ${testCount} Swift test cases. Swift compilation, XCTest, visual QA and device acceptance were NOT run on this Windows host.`);

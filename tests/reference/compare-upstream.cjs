// Development only: execute the actual pinned upstream TypeScript, not a JS rewrite.
// Usage: node compare-upstream.cjs "D:/.../Fantasy-Map-Generator"
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {stripTypeScriptTypes} = require('node:module');
const Alea = require('./alea.cjs');
const root = process.argv[2];
if (!root) throw new Error('Pass the pinned source checkout path.');
const scripts = ['src/data/heightmap-templates.ts', 'src/generators/heightmap-generator.ts', 'src/generators/grid-generator.ts'];
const {execFileSync} = require('node:child_process');
const commit = execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim();
if (commit !== '4305a1ab74515872db28b00f2f4f9c0c09f2a98c') throw new Error('Upstream checkout does not match the reference commit.');
execFileSync('git', ['-C', root, 'diff', '--quiet', 'HEAD', '--', ...scripts]);
const input = JSON.parse(fs.readFileSync(path.join(__dirname, 'graph-inputs.json'), 'utf8'));
const source = scripts.map(file => fs.readFileSync(path.join(root, file), 'utf8').replace(/^import .*;\r?$/gm, '').replace(/^export /gm, ''));
const runtime = {Alea, window: {}, Math: Object.create(Math), Uint8Array, console};
runtime.rand = (min, max) => Math.floor(runtime.Math.random() * (max - min + 1)) + min;
runtime.P = probability => probability >= 1 || (probability > 0 && runtime.Math.random() < probability);
runtime.getNumberInRange = value => {
  if (!Number.isNaN(+value)) return ~~value + +runtime.P(+value - ~~value);
  const sign = value[0] === '-' ? -1 : 1;
  if (Number.isNaN(+value[0])) value = value.slice(1);
  const [low, high] = value.split('-').map(parseFloat);
  return runtime.rand(low * sign, high);
};
runtime.lim = value => Math.min(Math.max(value, 0), 100);
runtime.minmax = (value, low, high) => Math.min(Math.max(value, low), high);
runtime.mean = array => array.reduce((a, b) => a + b, 0) / array.length;
runtime.d3Range = length => Array.from({length}, (_, i) => i);
runtime.leastIndex = (array, compare) => array.length ? array.reduce((best, value, i) => compare(value, array[best]) < 0 ? i : best, 0) : undefined;
runtime.Grid = {findCell: (x, y, graph) => Math.floor(Math.min(y / graph.spacing, graph.cellsY - 1)) * graph.cellsX + Math.floor(Math.min(x / graph.spacing, graph.cellsX - 1))};
runtime.TIME = false;
runtime.rn = (value, digits = 0) => Math.round(value * 10 ** digits) / 10 ** digits;
runtime.calculateVoronoi = () => ({cells: {}, vertices: {}}); // Geometry is checked separately in Godot.
vm.createContext(runtime);
vm.runInContext(source.map(text => stripTypeScriptTypes(text)).join('\n'), runtime, {timeout: 30000});
runtime.heightmapTemplates = runtime.window.heightmapTemplates;
const cases = input.map(data => {
  const sourceGraph = runtime.window.Grid.generate(data.seed, data.map_size[0], data.map_size[1], data.requested_points);
  const graph = {points: data.points.slice(0, data.heights.length), spacing: data.spacing, cellsX: data.columns, cellsY: data.rows,
    cells: {h: new Uint8Array(data.heights.length), c: data.neighbors}};
  const config = {width: data.map_size[0], height: data.map_size[1], points: data.requested_points};
  const results = {};
  for (const id of Object.keys(runtime.heightmapTemplates)) {
    runtime.Math.random = Alea(data.seed);
    results[id] = Array.from(runtime.window.HeightmapGenerator.fromTemplate(graph, id, config));
  }
  const random = Alea(data.seed);
  return {...data, source_points: sourceGraph.points, source_boundary: sourceGraph.boundary, results, random: Array.from({length: 32}, () => random.uint32())};
});
const unicodeRandom = Alea('legacy 🌋');
const hashes = Object.fromEntries(scripts.map(file => [file, require('node:crypto').createHash('sha256').update(fs.readFileSync(path.join(root, file))).digest('hex')]));
const output = {source_sha256: hashes, upstream_commit: commit,
  note: 'Actual upstream heightmap-generator.ts executed on Godot-generated Voronoi graph inputs. This proves cell operation parity on these graphs, not identical Delaunator ordering.',
  unicode_random: Array.from({length: 32}, () => unicodeRandom.uint32()), cases};
fs.writeFileSync(path.join(__dirname, 'heightmap-reference.json'), JSON.stringify(output));
console.log(`Generated ${cases.length * 14} upstream reference heightmaps.`);

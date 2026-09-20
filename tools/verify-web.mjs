// Drive the built game in a real browser and prove that it boots, renders and
// makes noise. Run it through tools/verify-web.sh, which installs what it needs.
//
// Audio is checked where it actually lands: the page's ScriptProcessorNode is
// wrapped before the wasm loads, so every block miniaudio mixes is measured on
// the way to the speakers. A silent run therefore fails even though nothing
// logs an error, which is what a missing or undecodable sound file looks like.
import { createServer } from 'node:http';
import { readFile, mkdir } from 'node:fs/promises';
import { extname, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

// Playwright is installed outside the checkout so it leaves no node_modules
// behind, and ESM ignores NODE_PATH, so the wrapper script points at it
// directly. A bare import still works for anyone who has it installed here.
const pkg = process.env.PLAYWRIGHT_MODULE ?? 'playwright';
const loaded = await import(pkg.startsWith('/') ? pathToFileURL(pkg).href : pkg);
// playwright is CommonJS, so imported by path its exports arrive under default.
const { chromium } = loaded.chromium ? loaded : loaded.default;

const DIST = resolve(process.env.DIST_DIR ?? 'dist');
const ARTIFACTS = resolve(process.env.ARTIFACTS_DIR ?? 'artifacts');
const PORT = Number(process.env.PORT ?? 8175);
const HEADFUL = process.env.HEADFUL === '1';

const TYPES = {
	'.html': 'text/html; charset=utf-8',
	'.js': 'text/javascript',
	'.wasm': 'application/wasm',
	'.data': 'application/octet-stream',
	'.png': 'image/png',
};

// Wrapped before any page script runs, so it is in place by the time the wasm
// runtime creates its audio graph.
const INSTRUMENT = () => {
	window.__audio = {
		blocks: 0,
		peak: 0,
		energy: 0,
		reset() {
			this.blocks = 0;
			this.peak = 0;
			this.energy = 0;
		},
	};
	const Ctx = window.AudioContext ?? window.webkitAudioContext;
	if (!Ctx) return;
	const create = Ctx.prototype.createScriptProcessor;
	const slot = Object.getOwnPropertyDescriptor(window.ScriptProcessorNode.prototype, 'onaudioprocess');
	Ctx.prototype.createScriptProcessor = function (...args) {
		const node = create.apply(this, args);
		Object.defineProperty(node, 'onaudioprocess', {
			configurable: true,
			get: () => slot.get.call(node),
			set(fn) {
				slot.set.call(node, function (event) {
					const result = fn.call(this, event);
					const samples = event.outputBuffer.getChannelData(0);
					let peak = 0;
					let energy = 0;
					for (let i = 0; i < samples.length; i++) {
						const value = Math.abs(samples[i]);
						if (value > peak) peak = value;
						energy += value;
					}
					const stats = window.__audio;
					stats.blocks++;
					if (peak > stats.peak) stats.peak = peak;
					stats.energy += energy / samples.length;
					return result;
				});
			},
		});
		return node;
	};
};

const serve = () =>
	new Promise((ready) => {
		const server = createServer(async (req, res) => {
			const path = (req.url ?? '/').split('?')[0];
			const file = join(DIST, path === '/' ? 'index.html' : path);
			try {
				const body = await readFile(file);
				res.writeHead(200, { 'content-type': TYPES[extname(file)] ?? 'application/octet-stream' });
				res.end(body);
			} catch {
				res.writeHead(404).end('not found');
			}
		});
		server.listen(PORT, '127.0.0.1', () => ready(server));
	});

const sleep = (ms) => new Promise((done) => setTimeout(done, ms));
const stats = (page) =>
	page.evaluate(() => ({ blocks: window.__audio.blocks, peak: window.__audio.peak, energy: window.__audio.energy }));

// Screenshots are diagnostics, not checks. Chromium renders this through
// SwiftShader and its compositor sometimes takes longer than the default
// timeout to hand over a stable frame, which is no reason to fail a run.
const shot = async (page, name) => {
	try {
		await page.screenshot({ path: join(ARTIFACTS, `${name}.png`), timeout: 60000 });
	} catch (error) {
		console.log(`note: could not capture ${name}.png (${error.message.split('\n')[0]})`);
	}
};

const failures = [];
const check = (ok, message) => {
	console.log(`${ok ? 'ok  ' : 'FAIL'} ${message}`);
	if (!ok) failures.push(message);
};

const server = await serve();
await mkdir(ARTIFACTS, { recursive: true });

const browser = await chromium.launch({
	headless: !HEADFUL,
	args: [
		// Headless Chromium has no GPU, so WebGL2 comes from SwiftShader.
		'--use-gl=angle',
		'--use-angle=swiftshader',
		'--enable-unsafe-swiftshader',
	],
});
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
const logs = [];
page.on('console', (message) => logs.push(`${message.type()}: ${message.text()}`));
page.on('pageerror', (error) => logs.push(`pageerror: ${error.message}`));
await page.addInitScript(INSTRUMENT);

try {
	await page.goto(`http://127.0.0.1:${PORT}/`, { waitUntil: 'domcontentloaded' });
	await page.waitForFunction(() => document.getElementById('loader')?.classList.contains('hidden'), null, {
		timeout: 120000,
	});
	check(true, 'wasm runtime started');

	// The boot splash runs for three seconds before the title screen.
	await sleep(3600);
	await shot(page, 'title');

	const beforeclick = await stats(page);
	// A click both starts the run and is the gesture browsers demand before
	// they let an AudioContext out of suspension.
	await page.mouse.click(640, 400);
	await sleep(1200);
	const music = await stats(page);
	check(music.blocks > beforeclick.blocks, `audio graph is running (${music.blocks} blocks mixed)`);
	check(music.peak > 0.01, `music is audible after the first click (peak ${music.peak.toFixed(3)})`);

	// Hold fire and fly around, which is where the shooting, hit and explosion
	// effects come from.
	await page.evaluate(() => window.__audio.reset());
	await page.mouse.move(640, 400);
	await page.mouse.down();
	for (const [x, y] of [[900, 300], [400, 520], [800, 560], [520, 260]]) {
		await page.mouse.move(x, y, { steps: 12 });
		await sleep(700);
	}
	await page.mouse.up();
	const playing = await stats(page);
	await shot(page, 'playing');
	check(playing.peak > 0.05, `effects are audible while firing (peak ${playing.peak.toFixed(3)})`);
	check(playing.energy / Math.max(1, playing.blocks) > 0.002,
		`output carries real signal (mean level ${(playing.energy / Math.max(1, playing.blocks)).toFixed(4)})`);

	// M mutes everything, including the music that is mid loop. Bullets already
	// in flight can still kill something a second after the trigger is
	// released, so let the field go quiet before measuring silence.
	await sleep(2000);
	await page.keyboard.press('m');
	await sleep(800);
	await page.evaluate(() => window.__audio.reset());
	await sleep(1200);
	const muted = await stats(page);
	await shot(page, 'muted');
	check(muted.blocks > 0 && muted.peak < 0.01, `M silences the mix (peak ${muted.peak.toFixed(4)})`);

	await page.keyboard.press('m');
	await page.evaluate(() => window.__audio.reset());
	await sleep(1000);
	const unmuted = await stats(page);
	check(unmuted.peak > 0.01, `M again brings it back (peak ${unmuted.peak.toFixed(3)})`);

	// Only uncaught exceptions are treated as failures. The engine writes plenty
	// of ordinary diagnostics to stderr, which arrive here as console errors.
	const crashes = logs.filter((line) => line.startsWith('pageerror'));
	check(crashes.length === 0, `no uncaught exceptions${crashes.length ? `: ${crashes.slice(0, 3).join(' | ')}` : ''}`);
	const stderr = logs.filter((line) => line.startsWith('error:'));
	if (stderr.length) console.log(`note: ${stderr.length} line(s) on stderr, first: ${stderr[0]}`);
} finally {
	if (process.env.VERBOSE === '1') console.log(logs.join('\n'));
	await browser.close();
	server.close();
}

console.log(`screenshots in ${ARTIFACTS}`);
if (failures.length) {
	console.error(`\n${failures.length} check(s) failed`);
	process.exit(1);
}
console.log('\nall checks passed');

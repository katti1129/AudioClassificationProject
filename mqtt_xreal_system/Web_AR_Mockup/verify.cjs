// Node integration checks with real Three.js geometry and camera mathematics.
// Only DOM, WebGL renderer and browser timing are replaced. This is NOT a
// browser/WebGL visual test. Run: node verify.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

(async () => {
  const three = await import(pathToFileURL(path.join(__dirname, 'vendor/three.module.js')));
  const elements = new Map();
  function element(id) {
    if (!elements.has(id)) elements.set(id, {
      value: '', checked: false, hidden: false, textContent: '', innerHTML: '', dataset: {}, attrs: {}, handlers: {}, style: { setProperty() {} },
      addEventListener(type, handler) { this.handlers[type] = handler; },
      setAttribute(key, value) { this.attrs[key] = value; },
      prepend() {}, getBoundingClientRect() { return { width: 1000, height: 700 }; },
      get valueAsNumber() { return Number(this.value); }
    });
    return elements.get(id);
  }
  const presets = [0, 90, 180, 270].map(deg => { const button = element(`preset${deg}`); button.dataset.doa = String(deg); return button; });
  let animation;
  const context = {
    THREE: { ...three, WebGLRenderer: class {
      constructor() { this.domElement = element('canvas'); }
      setPixelRatio() {} setSize() {} render() {} setAnimationLoop(callback) { animation = callback; }
    } },
    document: { getElementById: element, querySelectorAll: () => presets },
    window: { devicePixelRatio: 1 },
    ResizeObserver: class { constructor(callback) { this.callback = callback; } observe() { this.callback(); } },
    matchMedia: () => ({ matches: false }), console
  };
  const code = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8').replace(/^import .*;\r?\n/, '');
  vm.createContext(context);
  vm.runInContext(code + '\nglobalThis.inspect = { state, arrow, camera, mesh, material, geometry, displayAngle };', context);
  const { state, arrow, camera, material, geometry } = context.inspect;
  function input(id, value, type = 'input') {
    const control = element(id);
    if (type === 'change') control.checked = value;
    else control.value = String(value);
    control.handlers[type]({ target: control });
  }
  function click(deg) { element(`preset${deg}`).handlers.click(); }
  const close = (a, b) => assert.ok(Math.abs(a - b) < 1e-6, `${a} != ${b}`);
  const inside = () => {
    camera.updateMatrixWorld();
    const point = arrow.position.clone().project(camera);
    return Math.abs(point.x) <= 1 && Math.abs(point.y) <= 1 && Math.abs(point.z) <= 1;
  };
  let count = 0;
  function check(name, callback) { callback(); count++; console.log(`PASS ${name}`); }
  check('initial state and thick 3D mesh', () => {
    assert.equal(state.confidence, 98); assert.equal(arrow.visible, true);
    geometry.computeBoundingBox();
    assert.ok(geometry.boundingBox.max.y - geometry.boundingBox.min.y > 0.1);
    close(Math.hypot(arrow.position.x, arrow.position.z), 2.5);
    close(arrow.position.y, 1.05);
    close(context.inspect.mesh.rotation.x, 0);
  });
  check('all cardinal presets, position AND outward arrow orientation', () => {
    for (const [deg, x, z] of [[0, 0, -2.5], [90, 2.5, 0], [180, 0, 2.5], [270, -2.5, 0]]) {
      click(deg); close(arrow.position.x, x); close(arrow.position.z, z);
      const forward = new three.Vector3(0, 0, -1).applyQuaternion(arrow.quaternion);
      close(forward.x, x / 2.5); close(forward.z, z / 2.5);
      assert.equal(JSON.parse(element('payload').textContent).doa_deg, deg);
    }
  });
  check('detection switches mesh AND warning, preserving payload boolean', () => {
    input('detected', false, 'change'); assert.equal(arrow.visible, false); assert.equal(element('alert').hidden, true);
    assert.equal(JSON.parse(element('payload').textContent).detected, false);
    input('detected', true, 'change'); assert.equal(arrow.visible, true); assert.equal(element('alert').hidden, false);
  });
  check('offset + inversion order and raw payload DOA', () => {
    input('doa', 45); input('offset', 30); assert.equal(context.inspect.displayAngle(), 75);
    input('invert', true, 'change'); assert.equal(context.inspect.displayAngle(), 345);
    assert.equal(JSON.parse(element('payload').textContent).doa_deg, 45);
    input('offset', -180); assert.equal(context.inspect.displayAngle(), 135);
    input('invert', false, 'change'); input('offset', 0);
  });
  check('back hidden at yaw 0, visible at +/-180; world position and DOA stay fixed', () => {
    click(180); input('yaw', 0); assert.equal(inside(), false);
    const original = arrow.position.clone();
    for (const yaw of [180, -180]) { input('yaw', yaw); assert.equal(inside(), true); assert.equal(state.doa, 180); assert.ok(arrow.position.equals(original)); }
    input('yaw', 0);
  });
  check('confidence color boundaries, clear labels, unchanged size and payload schema', () => {
    animation(0); const scale = arrow.scale.clone();
    for (const [value, color, title] of [[0, 0xb4c1cf, '救急車の可能性'], [49.9, 0xb4c1cf, '救急車の可能性'], [50, 0xffc44f, '救急車の可能性'], [79.9, 0xffc44f, '救急車の可能性'], [80, 0xff554f, '救急車'], [100, 0xff554f, '救急車']]) {
      input('confidence', value);
      assert.ok(arrow.scale.equals(scale));
      assert.equal(material.color.getHex(), color);
      assert.equal(element('alert-title').textContent, title);
      assert.equal(arrow.visible, true);
    }
    const html = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
    assert.ok(!html.includes('id="alert-confidence"'));
    input('confidence', 100); const data = JSON.parse(element('payload').textContent);
    assert.equal(data.confidence_pct, 100);
    assert.deepEqual(Object.keys(data), ['version', 'detected', 'class_name', 'confidence_pct', 'doa_deg', 'rms', 'inference_ms', 'timestamp_ms']);
    assert.ok(Number.isInteger(data.timestamp_ms));
  });
  check('number input clamps, rounds and recovers from empty input', () => {
    input('doa-number', 999); assert.equal(state.doa, 359);
    input('doa-number', -3); assert.equal(state.doa, 0);
    input('doa-number', 45.6); assert.equal(state.doa, 46);
    input('doa-number', ''); element('doa-number').handlers.blur(); assert.equal(element('doa-number').value, 46);
  });
  check('pulse 1 to 1.1 over four seconds', () => {
    animation(0); close(arrow.scale.x, 1); animation(2000); close(arrow.scale.x, 1.1); animation(4000); close(arrow.scale.x, 1);
  });
  check('Demo wraps, updates JSON, stops on preset and manual input', () => {
    input('doa', 359); element('demo').handlers.click(); animation(4100); animation(4200);
    assert.ok(state.doa < 5); assert.equal(JSON.parse(element('payload').textContent).doa_deg, state.doa);
    click(0); assert.equal(state.demo, false);
    element('demo').handlers.click(); input('doa', 25); assert.equal(state.demo, false);
  });
  console.log(`${count} integration groups passed. Browser rendering not exercised.`);
})().catch(error => { console.error(error); process.exitCode = 1; });

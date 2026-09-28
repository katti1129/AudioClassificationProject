import * as THREE from './vendor/three.module.js';

const $ = id => document.getElementById(id);
const state = { doa: 20, offset: 0, invert: false, detected: true, confidence: 98, yaw: 0, demo: false };
const RADIUS = 2.5;
const EYE_HEIGHT = 1.6;
const ARROW_HEIGHT = 1.05; // Below eye level so the horizontal top stays visible.
// Provisional visual thresholds for this mockup; not calibrated probabilities.
const CONFIDENCE_BANDS = [
  { min: 80, color: 0xff554f, emissive: 0xd72d24, title: '救急車', label: 'サイレンを検知' },
  { min: 50, color: 0xffc44f, emissive: 0xbf7d15, title: '救急車の可能性', label: 'サイレンらしい音を検知' },
  { min: 0, color: 0xb4c1cf, emissive: 0x536a82, title: '救急車の可能性', label: '音の種類を確認中' }
];
const normalize = angle => ((angle % 360) + 360) % 360;
const radians = degrees => degrees * Math.PI / 180;
// Calibration follows the existing subscriber: invert raw DOA, then add offset.
const displayAngle = () => normalize((state.invert ? -state.doa : state.doa) + state.offset);
const viewport = $('viewport');
const scene = new THREE.Scene();
scene.background = new THREE.Color(0x263b49);
scene.fog = new THREE.Fog(0x263b49, 20, 110);
const camera = new THREE.PerspectiveCamera(64, 1, 0.05, 150);
camera.position.set(0, EYE_HEIGHT, 0);
const renderer = new THREE.WebGLRenderer({ antialias: true });
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.outputColorSpace = THREE.SRGBColorSpace;
viewport.prepend(renderer.domElement);
renderer.domElement.setAttribute('aria-label', '道路と建物の3D空間。検知時に音源方向の立体矢印を表示');
renderer.domElement.addEventListener('webglcontextlost', event => {
  event.preventDefault();
  $('error').hidden = false;
  $('error').textContent = 'WebGLの描画が停止しました。ページを再読み込みしてください。';
});
scene.add(new THREE.HemisphereLight(0xd5ebff, 0x27333b, 2.5));
const sun = new THREE.DirectionalLight(0xffdfb9, 3);
sun.position.set(-12, 22, 8);
scene.add(sun);

function box(w, h, d, x, y, z, color, emissive = 0) {
  const mesh = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), new THREE.MeshStandardMaterial({ color, roughness: 0.85, emissive, emissiveIntensity: 0.3 }));
  mesh.position.set(x, y, z);
  scene.add(mesh);
  return mesh;
}
box(230, 0.12, 230, 0, -0.12, 0, 0x30434b);
box(10, 0.04, 220, 0, -0.025, 0, 0x263038);
for (const side of [-1, 1]) {
  box(2.2, 0.16, 220, side * 6.1, 0, 0, 0x596a70);
  box(0.09, 0.012, 220, side * 4.6, 0.008, 0, 0xa4b1ad);
  for (let i = -7; i <= 7; i++) {
    const z = i * 14 + 5;
    const height = 5 + ((i + 8) * 7 % 11);
    box(7, height, 9, side * 12, height / 2, z, i % 2 ? 0x445865 : 0x354a57);
    box(7.3, 0.22, 9.3, side * 12, height, z, 0x71828a);
    for (let floor = 2; floor < height - 1; floor += 2.4) {
      for (let windowZ = -2.7; windowZ <= 2.7; windowZ += 2.7) {
        box(0.025, 0.95, 1.4, side * 8.485, floor, z + windowZ, 0x7d9a9f, 0x55787d);
      }
    }
    box(0.09, 4.8, 0.09, side * 6.4, 2.4, z, 0x7a8f96);
    box(0.8, 0.07, 0.25, side * 6.1, 4.8, z, 0xb4c7c7, 0x8db8bf);
  }
}
for (let z = -100; z < 100; z += 6) box(0.1, 0.015, 2.6, 0, 0.009, z, 0xc5b886);
// Thick, bevelled arrow lying flat in the XZ plane, pointing along local -Z.
// Lower placement exposes its top without tilting the arrow upward.
const outline = new THREE.Shape();
outline.moveTo(-0.14, -0.48);
outline.lineTo(0.14, -0.48);
outline.lineTo(0.14, 0.05);
outline.lineTo(0.37, 0.05);
outline.lineTo(0, 0.55);
outline.lineTo(-0.37, 0.05);
outline.lineTo(-0.14, 0.05);
outline.closePath();
const geometry = new THREE.ExtrudeGeometry(outline, { depth: 0.13, bevelEnabled: true, bevelSize: 0.035, bevelThickness: 0.025, bevelSegments: 3, steps: 1 });
geometry.translate(0, 0, -0.065);
geometry.rotateX(-Math.PI / 2);
const material = new THREE.MeshStandardMaterial({ color: 0xffae48, emissive: 0xf78021, emissiveIntensity: 0.5, metalness: 0.24, roughness: 0.32 });
const arrow = new THREE.Group();
const mesh = new THREE.Mesh(geometry, material);
mesh.rotation.x = 0;
arrow.add(mesh);
scene.add(arrow);

function setDemo(enabled) {
  state.demo = enabled;
  $('demo').setAttribute('aria-pressed', String(enabled));
  $('demo').innerHTML = enabled ? 'Ⅱ Stop Demo <span>手動DOA操作でも停止</span>' : '▶ Demo <span>ゆっくり360°回転</span>';
  demoAngle = state.doa;
}
function payload() {
  return { version: 1, detected: state.detected, class_name: state.detected ? 'siren' : 'background', confidence_pct: state.confidence, doa_deg: state.doa, rms: 0.041, inference_ms: 23.8, timestamp_ms: Date.now() };
}
function update() {
  const angle = displayAngle();
  const theta = radians(angle);
  // Three.js default view is -Z; Unity's conceptual +Z forward is mirrored here.
  arrow.position.set(RADIUS * Math.sin(theta), ARROW_HEIGHT, -RADIUS * Math.cos(theta));
  arrow.rotation.y = -theta;
  arrow.visible = state.detected;
  camera.rotation.y = -radians(state.yaw);
  $('alert').hidden = !state.detected;
  const band = CONFIDENCE_BANDS.find(item => state.confidence >= item.min);
  material.color.setHex(band.color);
  material.emissive.setHex(band.emissive);
  $('alert-title').textContent = band.title;
  $('alert-status').textContent = band.label;
  $('alert').style.setProperty('--signal', `#${band.color.toString(16).padStart(6, '0')}`);
  $('display-angle').textContent = `${angle}°`;
  $('yaw-readout').textContent = `${state.yaw}°`;
  $('heading').textContent = `HEAD ${state.yaw}°`;
  $('position').textContent = `${arrow.position.x.toFixed(2)} / ${arrow.position.z.toFixed(2)} m`;
  $('payload').textContent = JSON.stringify(payload(), null, 2);
  for (const key of ['doa', 'offset', 'yaw', 'confidence']) $(key).value = state[key];
  $('doa-number').value = state.doa;
  $('offset-value').textContent = `${state.offset}°`;
  $('yaw-value').textContent = `${state.yaw}°`;
  $('confidence-value').textContent = `${state.confidence.toFixed(1)}%`;
  document.querySelectorAll('[data-doa]').forEach(button => button.setAttribute('aria-pressed', String(Number(button.dataset.doa) === state.doa)));
  updateVisibility();
}
function updateVisibility() {
  const relative = normalize(displayAngle() - state.yaw + 180) - 180;
  const horizontalFov = 2 * Math.atan(Math.tan(radians(camera.fov) / 2) * camera.aspect) * 180 / Math.PI;
  $('visibility').textContent = !state.detected ? 'MONITORING · 検知なし' : Math.abs(relative) < horizontalFov / 2 ? 'ARROW · 視野内' : `ARROW · 視野外 / Head Yawで確認`;
}
let demoAngle = state.doa;
for (const key of ['doa', 'offset', 'yaw', 'confidence']) {
  $(key).addEventListener('input', event => {
    if (key === 'doa') setDemo(false);
    state[key] = Number(event.target.value);
    update();
  });
}
function readDoaNumber() {
  const input = $('doa-number');
  if (input.value === '' || !Number.isFinite(input.valueAsNumber)) return;
  setDemo(false);
  state.doa = Math.max(0, Math.min(359, Math.round(input.valueAsNumber)));
  update();
}
$('doa-number').addEventListener('input', readDoaNumber);
$('doa-number').addEventListener('blur', () => { $('doa-number').value = state.doa; });
for (const key of ['detected', 'invert']) $(key).addEventListener('change', event => { state[key] = event.target.checked; update(); });
document.querySelectorAll('[data-doa]').forEach(button => button.addEventListener('click', () => { setDemo(false); state.doa = Number(button.dataset.doa); update(); }));
$('demo').addEventListener('click', () => setDemo(!state.demo));
new ResizeObserver(() => {
  const { width, height } = viewport.getBoundingClientRect();
  renderer.setSize(width, height);
  camera.aspect = width / height;
  camera.updateProjectionMatrix();
  updateVisibility();
}).observe(viewport);
const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)');
let previousTime;
function frame(time) {
  const delta = previousTime === undefined ? 0 : Math.min((time - previousTime) / 1000, 0.1);
  previousTime = time;
  if (state.demo) {
    demoAngle = normalize(demoAngle + delta * 12); // One revolution per 30 s.
    const next = Math.floor(demoAngle);
    if (next !== state.doa) { state.doa = next; update(); }
  }
  const pulse = reduceMotion.matches ? 1 : 1 + 0.05 * (1 - Math.cos(time / 1000 * Math.PI / 2));
  arrow.scale.setScalar(pulse); // Smooth 4 s cycle, 1.0 .. 1.1.
  renderer.render(scene, camera);
}
update();
renderer.setAnimationLoop(frame);

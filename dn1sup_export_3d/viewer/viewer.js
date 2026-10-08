import * as THREE from "three";
import { GLTFLoader } from "./vendor/three/GLTFLoader.js";
import { OrbitControls } from "./vendor/three/OrbitControls.js";

const canvas = document.getElementById("viewport");
const info = document.getElementById("info");
const status = document.getElementById("status");

const scene = new THREE.Scene();
scene.background = new THREE.Color(0x1e1f24);

const camera = new THREE.PerspectiveCamera(45, 1, 0.01, 1000);
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));

const controls = new OrbitControls(camera, renderer.domElement);
controls.enableDamping = true;

scene.add(new THREE.HemisphereLight(0xffffff, 0x444455, 2.0));
const dirLight = new THREE.DirectionalLight(0xffffff, 2.0);
dirLight.position.set(5, 10, 7);
scene.add(dirLight);

const modelRoot = new THREE.Group();
scene.add(modelRoot);

let modelBox = null;
let selectedPid = null;
const meshesByPid = new Map(); // "persistent_id" -> [mesh]
const originalMaterials = new Map(); // mesh -> material (while highlighted)
const listeners = new Map(); // event name -> [callback]

function emit(event, detail) {
  (listeners.get(event) || []).forEach((cb) => {
    try { cb(detail); } catch (err) { console.error(`viewer event '${event}' handler failed`, err); }
  });
}

function on(event, callback) {
  if (!listeners.has(event)) listeners.set(event, []);
  listeners.get(event).push(callback);
}

// GLTFLoader assigns glTF node.extras to node.userData; renderable meshes are
// children of those nodes, so inherit the nearest ancestor's metadata for
// picking and identification.
function inheritExtras(root) {
  root.traverse((obj) => {
    let node = obj;
    while (node) {
      if (node.userData && node.userData.sketchup) {
        obj.userData.sketchup = node.userData.sketchup;
        return;
      }
      node = node.parent;
    }
  });
}

function collectMeshes(root) {
  meshesByPid.clear();
  let triangles = 0;
  root.traverse((obj) => {
    if (!obj.isMesh) return;
    const geometry = obj.geometry;
    triangles += geometry.index ? geometry.index.count / 3 : geometry.attributes.position.count / 3;
    const pid = obj.userData && obj.userData.sketchup && obj.userData.sketchup.persistent_id;
    if (pid !== undefined) {
      const key = String(pid);
      if (!meshesByPid.has(key)) meshesByPid.set(key, []);
      meshesByPid.get(key).push(obj);
    }
  });
  return triangles;
}

function setHighlight(pid) {
  originalMaterials.forEach((material, mesh) => { mesh.material = material; });
  originalMaterials.clear();
  selectedPid = null;
  if (pid === null || pid === undefined) return;
  const meshes = meshesByPid.get(String(pid)) || [];
  // Instance meshes share glTF materials, so highlight via per-mesh clones.
  meshes.forEach((mesh) => {
    if (!mesh.material) return;
    originalMaterials.set(mesh, mesh.material);
    const highlight = mesh.material.clone();
    if (highlight.emissive) {
      highlight.emissive = new THREE.Color(0x3355aa);
      highlight.emissiveIntensity = 0.6;
    }
    mesh.material = highlight;
  });
  if (meshes.length) selectedPid = String(pid);
}

function formatExtras(sketchup) {
  if (!sketchup) return "";
  return `name: ${sketchup.name || "-"}\n` +
    `type: ${sketchup.entity_type || "-"}\n` +
    `persistent_id: ${sketchup.persistent_id}\n` +
    `layer: ${sketchup.layer || "-"}`;
}

function clearSelection() {
  setHighlight(null);
  info.style.display = "none";
  emit("selectionCleared");
}

function getObject(pid) {
  const meshes = meshesByPid.get(String(pid));
  if (!meshes || meshes.length === 0) return null;
  return (meshes[0].userData && meshes[0].userData.sketchup) || null;
}

function selectObject(pid) {
  if (!meshesByPid.has(String(pid))) return false;
  setHighlight(pid);
  const sketchup = getObject(pid);
  info.textContent = formatExtras(sketchup);
  info.style.display = "block";
  emit("objectSelected", sketchup);
  return true;
}

function focusObject(pid) {
  const meshes = meshesByPid.get(String(pid));
  if (!meshes || meshes.length === 0) return false;
  const box = new THREE.Box3();
  meshes.forEach((mesh) => box.expandByObject(mesh));
  if (box.isEmpty()) return false;
  fitTo(box);
  return true;
}

function fitTo(box) {
  const sphere = box.getBoundingSphere(new THREE.Sphere());
  const center = sphere.center.clone();
  const radius = Math.max(sphere.radius, 0.001);
  const dist = radius / Math.sin(THREE.MathUtils.degToRad(camera.fov / 2));
  camera.position.copy(center).addScaledVector(new THREE.Vector3(1, 0.8, 1).normalize(), dist);
  camera.near = radius / 100;
  camera.far = dist * 10;
  camera.updateProjectionMatrix();
  controls.target.copy(center);
  controls.update();
}

function fit() {
  if (modelBox) fitTo(modelBox);
}

// JS -> Ruby bridge: HtmlDialog action callbacks are invoked through the
// skp: scheme; only attempt it when running inside SketchUp.
function notifySketchUp(callback, argument) {
  if (!/SketchUp/i.test(navigator.userAgent)) return;
  window.location.href = "skp:" + callback + "@" + (argument === undefined ? "" : argument);
}

function loadModel(url) {
  status.textContent = "Loading…";
  const loader = new GLTFLoader();
  loader.load(
    url,
    (gltf) => {
      setHighlight(null);
      modelRoot.clear();
      modelRoot.add(gltf.scene);
      inheritExtras(modelRoot);
      modelBox = new THREE.Box3().setFromObject(modelRoot);
      const triangles = Math.round(collectMeshes(modelRoot));
      fit();
      status.textContent = `Loaded: ${meshesByPid.size} selectable objects, ${triangles} triangles`;
      emit("viewerReady", { url: url, objects: meshesByPid.size, triangles: triangles });
      notifySketchUp("viewer_ready", String(meshesByPid.size));
    },
    undefined,
    (err) => {
      status.textContent = "Failed to load GLB: " + err;
      console.error(err);
      emit("loadError", { url: url, error: String(err) });
    }
  );
}

// ------------------------------------------------------------- public API

const api = {
  loadModel: loadModel,
  selectObject: selectObject,
  focusObject: focusObject,
  getObject: getObject,
  clearSelection: clearSelection,
  fit: fit,
  reset: fit,
  on: on,
  get selectedPid() { return selectedPid; },
};
window.viewer = api;

// --------------------------------------------------------------- toolbar

document.getElementById("btn-fit").onclick = fit;
document.getElementById("btn-reset").onclick = fit;
let wireframe = false;
document.getElementById("btn-wire").onclick = () => {
  wireframe = !wireframe;
  modelRoot.traverse((obj) => {
    if (obj.isMesh && obj.material) obj.material.wireframe = wireframe;
  });
};

// -------------------------------------------------------------- picking

canvas.addEventListener("pointerdown", (e) => {
  const rect = canvas.getBoundingClientRect();
  const pointer = new THREE.Vector2(
    ((e.clientX - rect.left) / rect.width) * 2 - 1,
    -((e.clientY - rect.top) / rect.height) * 2 + 1
  );
  const raycaster = new THREE.Raycaster();
  raycaster.setFromCamera(pointer, camera);
  const hits = raycaster.intersectObjects(modelRoot.children, true);
  const hit = hits.find((h) => h.object.isMesh);
  const sketchup = hit && hit.object.userData && hit.object.userData.sketchup;
  if (sketchup && sketchup.persistent_id !== undefined) {
    selectObject(sketchup.persistent_id);
    notifySketchUp("object_selected", String(sketchup.persistent_id));
  } else {
    clearSelection();
  }
});

function animate() {
  requestAnimationFrame(animate);
  controls.update();
  renderer.render(scene, camera);
}

function resize() {
  const w = canvas.clientWidth || window.innerWidth;
  const h = canvas.clientHeight || window.innerHeight;
  renderer.setSize(w, h, false);
  camera.aspect = w / h;
  camera.updateProjectionMatrix();
}
window.addEventListener("resize", resize);
resize();
animate();

const modelUrl = new URLSearchParams(location.search).get("model") || "./model.glb";
loadModel(modelUrl);

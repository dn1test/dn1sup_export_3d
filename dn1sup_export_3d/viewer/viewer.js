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

const controls = new OrbitControls(camera, renderer.domElement);
controls.enableDamping = true;

const hemi = new THREE.HemisphereLight(0xffffff, 0x444455, 2.0);
scene.add(hemi);
const dir = new THREE.DirectionalLight(0xffffff, 2.0);
dir.position.set(5, 10, 7);
scene.add(dir);

const modelRoot = new THREE.Group();
scene.add(modelRoot);

let modelBox = null;
const meshIdMap = new Map();

function fit() {
  if (!modelBox) return;
  const sphere = modelBox.getBoundingSphere(new THREE.Sphere());
  const center = sphere.center.clone();
  const radius = Math.max(sphere.radius, 0.001);
  const dist = radius / Math.sin(THREE.MathUtils.degToRad(camera.fov / 2));
  const dirV = new THREE.Vector3(1, 0.8, 1).normalize();
  camera.position.copy(center).addScaledVector(dirV, dist);
  camera.near = radius / 100;
  camera.far = dist * 10;
  camera.updateProjectionMatrix();
  controls.target.copy(center);
  controls.update();
}

function reset() {
  fit();
}

function collectMeshes(root) {
  const meshes = [];
  root.traverse((o) => {
    if (o.isMesh) {
      meshes.push(o);
      const pid = o.userData?.sketchup?.persistent_id;
      if (pid !== undefined) meshIdMap.set(String(pid), o);
    }
  });
  return meshes;
}

function selectByPid(pid) {
  modelRoot.traverse((o) => {
    if (o.isMesh) o.material.emissive?.setHex(0x000000);
  });
  const mesh = meshIdMap.get(String(pid));
  if (mesh?.material?.emissive) mesh.material.emissive.setHex(0x3355aa);
}

function formatExtras(extras) {
  if (!extras?.sketchup) return "";
  const s = extras.sketchup;
  return `name: ${s.name || "-"}\ntype: ${s.entity_type}\npersistent_id: ${s.persistent_id}`;
}

function loadModel(url) {
  status.textContent = "Loading…";
  const loader = new GLTFLoader();
  loader.load(
    url,
    (gltf) => {
      modelRoot.clear();
      modelRoot.add(gltf.scene);
      modelBox = new THREE.Box3().setFromObject(modelRoot);
      collectMeshes(modelRoot);
      fit();
      const tris = renderer.info.render.triangles;
      status.textContent = `Loaded: ${modelRoot.children[0]?.children?.length ?? 0} root nodes`;
      window.__viewer = { selectByPid, fit, reset, model: gltf.scene };
      window.dispatchEvent(new CustomEvent("viewerReady", { detail: { loaded: true } }));
    },
    undefined,
    (err) => {
      status.textContent = "Failed to load GLB: " + err;
      console.error(err);
    }
  );
}

document.getElementById("btn-fit").onclick = fit;
document.getElementById("btn-reset").onclick = reset;
let wire = false;
document.getElementById("btn-wire").onclick = () => {
  wire = !wire;
  modelRoot.traverse((o) => {
    if (o.isMesh) o.material.wireframe = wire;
  });
};

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
  if (hit) {
    selectByPid(hit.object.userData?.sketchup?.persistent_id ?? "");
    const text = formatExtras(hit.object.userData);
    if (text) {
      info.textContent = text;
      info.style.display = "block";
      window.dispatchEvent(new CustomEvent("objectSelected", { detail: hit.object.userData.sketchup }));
    }
  } else {
    info.style.display = "none";
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
  renderer.setSize(window.innerWidth, window.innerHeight, false);
  camera.aspect = w / h;
  camera.updateProjectionMatrix();
}
window.addEventListener("resize", resize);
resize();
animate();

const url = new URLSearchParams(location.search).get("model") || "./model.glb";
loadModel(url);

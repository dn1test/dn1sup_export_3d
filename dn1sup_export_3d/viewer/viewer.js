import * as THREE from "three";
import { GLTFLoader } from "./vendor/three/GLTFLoader.js";
import { OrbitControls } from "./vendor/three/OrbitControls.js";

const canvas = document.getElementById("viewport");
const info = document.getElementById("info");
const status = document.getElementById("status");
const treeBox = document.getElementById("tree");
const treeFilter = document.getElementById("tree-filter");

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
const extrasByPid = new Map(); // "persistent_id" -> extras.sketchup
const nodesByPid = new Map(); // "persistent_id" -> owning node (for visibility)
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
// children of those nodes. Collect the full ancestor chain of metadata
// (nearest owning object first, outermost component instance last) so clicks
// can identify both the part and the instance it belongs to. sketchupOwn
// marks the nodes that carry extras themselves (tree + visibility targets).
function inheritExtras(root) {
  root.traverse((obj) => {
    const own = obj.userData && obj.userData.sketchup ? obj.userData.sketchup : null;
    const chain = [];
    let node = obj;
    while (node) {
      if (node.userData && node.userData.sketchup) chain.push(node.userData.sketchup);
      node = node.parent;
    }
    if (chain.length) {
      obj.userData.sketchup = chain[0];
      obj.userData.sketchupChain = chain;
      obj.userData.sketchupOwn = own;
    }
  });
}

function collectMeshes(root) {
  meshesByPid.clear();
  extrasByPid.clear();
  nodesByPid.clear();
  let triangles = 0;
  root.traverse((obj) => {
    if (!obj.isMesh) return;
    const geometry = obj.geometry;
    triangles += geometry.index ? geometry.index.count / 3 : geometry.attributes.position.count / 3;
    const chain = obj.userData.sketchupChain || [];
    chain.forEach((sketchup) => {
      const key = String(sketchup.persistent_id);
      if (!meshesByPid.has(key)) meshesByPid.set(key, []);
      meshesByPid.get(key).push(obj);
      extrasByPid.set(key, sketchup);
    });
  });
  // Separate pass: owning nodes may be non-mesh containers.
  root.traverse((obj) => {
    const own = obj.userData && obj.userData.sketchupOwn;
    if (own && own.persistent_id !== undefined) {
      nodesByPid.set(String(own.persistent_id), obj);
    }
  });
  return triangles;
}

// Hidden subtrees must not be pickable (Raycaster ignores .visible itself).
function isShown(object) {
  for (let node = object; node; node = node.parent) {
    if (node.visible === false) return false;
  }
  return true;
}

function setHighlight(pid) {
  originalMaterials.forEach((material, mesh) => { mesh.material = material; });
  originalMaterials.clear();
  selectedPid = null;
  if (pid === null || pid === undefined) {
    syncTree(null);
    return;
  }
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
  syncTree(selectedPid);
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
  const key = String(pid);
  if (!meshesByPid.has(key)) return null;
  return extrasByPid.get(key) || null;
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

// Viewer-side visibility of an object (AGENTS.md #19); does not touch the GLB.
function setShowObject(pid, visible) {
  const node = nodesByPid.get(String(pid));
  if (!node) return false;
  node.visible = !!visible;
  const row = treeBox.querySelector(
    `li[data-pid="${String(pid)}"] > details > summary > .tree-row, ` +
    `li[data-pid="${String(pid)}"] > .tree-row`
  );
  if (row) row.classList.toggle("hidden-object", !visible);
  emit("objectVisibilityChanged", { pid: String(pid), visible: !!visible });
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

// JS -> Ruby bridge: HtmlDialog injects a global `sketchup` object whose
// properties are the registered action callbacks; absent in normal browsers.
function notifySketchUp(callback, args) {
  const bridge = window.sketchup;
  if (!bridge || typeof bridge[callback] !== "function") return;
  bridge[callback].apply(bridge, args);
}

// ------------------------------------------------------------- object tree

function displayName(skp) {
  return (skp && skp.name && skp.name.trim()) || (skp && skp.entity_type) || "Object";
}

function makeRow(skp) {
  const row = document.createElement("div");
  row.className = "tree-row";
  const caret = document.createElement("span");
  caret.className = "caret";
  caret.textContent = "\u25B6";
  row.appendChild(caret);
  const badge = document.createElement("span");
  badge.className = "badge " + (skp.entity_type || "Object").charAt(0);
  badge.textContent = (skp.entity_type || "Object").charAt(0);
  badge.title = skp.entity_type || "Object";
  row.appendChild(badge);
  const name = document.createElement("span");
  name.className = "name";
  name.textContent = displayName(skp);
  name.title = `${displayName(skp)} (${skp.persistent_id})`;
  row.appendChild(name);
  const eye = document.createElement("button");
  eye.className = "eye";
  eye.textContent = "\u{1F441}";
  eye.title = "Show/hide";
  eye.onclick = (e) => {
    e.stopPropagation();
    const node = nodesByPid.get(String(skp.persistent_id));
    setShowObject(skp.persistent_id, node ? node.visible === false : false);
  };
  row.appendChild(eye);
  row.onclick = () => userSelect(skp.persistent_id);
  return row;
}

function buildBranch(parentObject) {
  const ul = document.createElement("ul");
  parentObject.children.forEach((child) => {
    const own = child.userData && child.userData.sketchupOwn;
    if (!own || own.persistent_id === undefined) {
      // Wrapper node without identity (e.g. the glTF scene group): splice its
      // entries up one level instead of nesting another list.
      if (child.children.length) {
        const nested = buildBranch(child);
        Array.from(nested.children).forEach((li) => ul.appendChild(li));
      }
      return;
    }
    const li = document.createElement("li");
    li.dataset.pid = String(own.persistent_id);
    if (child.children.length) {
      const details = document.createElement("details");
      const summary = document.createElement("summary");
      summary.appendChild(makeRow(own));
      details.appendChild(summary);
      details.appendChild(buildBranch(child));
      li.appendChild(details);
    } else {
      const row = makeRow(own);
      row.querySelector(".caret").style.visibility = "hidden";
      li.appendChild(row);
    }
    ul.appendChild(li);
  });
  return ul;
}

function buildTree() {
  treeBox.textContent = "";
  treeBox.appendChild(buildBranch(modelRoot));
  applyTreeFilter(treeFilter.value);
}

function syncTree(pid) {
  treeBox.querySelectorAll(".tree-row.selected").forEach((row) => row.classList.remove("selected"));
  if (pid === null || pid === undefined) return;
  const li = treeBox.querySelector(`li[data-pid="${String(pid)}"]`);
  if (!li) return;
  const row = li.querySelector(".tree-row");
  if (row) row.classList.add("selected");
  let ancestor = li.parentElement;
  while (ancestor && ancestor !== treeBox) {
    if (ancestor.tagName === "DETAILS") ancestor.open = true;
    ancestor = ancestor.parentElement;
  }
  if (row) row.scrollIntoView({ block: "nearest" });
}

// Hides rows that do not match; keeps ancestors of matches visible and open.
function applyTreeFilter(query) {
  const q = query.trim().toLowerCase();

  function filterUl(ul) {
    let any = false;
    Array.from(ul.children).forEach((node) => {
      if (node.tagName === "UL") {
        if (filterUl(node)) any = true;
        return;
      }
      const row = node.querySelector(".tree-row");
      const nested = node.querySelector(":scope > details > ul");
      const childMatch = nested ? filterUl(nested) : false;
      const text = row ? row.textContent.toLowerCase() : "";
      const selfMatch = q === "" || text.includes(q);
      const show = selfMatch || childMatch;
      node.style.display = show ? "" : "none";
      const details = node.querySelector(":scope > details");
      if (details) details.open = q !== "" && childMatch;
      if (show) any = true;
    });
    return any;
  }

  filterUl(treeBox);
}

function userSelect(pid) {
  if (!selectObject(pid)) return false;
  notifySketchUp("object_selected", [String(pid)]);
  return true;
}

// ------------------------------------------------------------------ load

function loadModel(url) {
  status.textContent = "Loading\u2026";
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
      buildTree();
      fit();
      status.textContent = `Loaded: ${meshesByPid.size} selectable objects, ${triangles} triangles`;
      emit("viewerReady", { url: url, objects: meshesByPid.size, triangles: triangles });
      notifySketchUp("viewer_ready", [String(meshesByPid.size)]);
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
  setShowObject: setShowObject,
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
document.getElementById("btn-tree").onclick = () => {
  document.body.classList.toggle("side-hidden");
  resize();
};
treeFilter.addEventListener("input", () => applyTreeFilter(treeFilter.value));

// -------------------------------------------------------------- picking

function pickAt(clientX, clientY) {
  const rect = canvas.getBoundingClientRect();
  const pointer = new THREE.Vector2(
    ((clientX - rect.left) / rect.width) * 2 - 1,
    -((clientY - rect.top) / rect.height) * 2 + 1
  );
  const raycaster = new THREE.Raycaster();
  raycaster.setFromCamera(pointer, camera);
  const hits = raycaster.intersectObjects(modelRoot.children, true);
  return hits.find((h) => h.object.isMesh && isShown(h.object)) || null;
}

canvas.addEventListener("pointerdown", (e) => {
  const hit = pickAt(e.clientX, e.clientY);
  const chain = (hit && hit.object.userData && hit.object.userData.sketchupChain) || [];
  if (chain.length) {
    // Identify the outermost object (the component instance that was hit)
    // while keeping the whole ancestor chain for the Ruby side: it selects
    // the first pid that actually exists as an entity in the model.
    const outermost = chain[chain.length - 1];
    const chainPids = chain.map((sketchup) => String(sketchup.persistent_id));
    selectObject(outermost.persistent_id);
    emit("objectSelected", { ...chain[0], chain: chainPids });
    notifySketchUp("object_selected", chainPids);
  } else {
    clearSelection();
  }
});

canvas.addEventListener("dblclick", (e) => {
  const hit = pickAt(e.clientX, e.clientY);
  const chain = (hit && hit.object.userData && hit.object.userData.sketchupChain) || [];
  if (chain.length) {
    const outermost = chain[chain.length - 1];
    userSelect(outermost.persistent_id);
    focusObject(outermost.persistent_id);
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

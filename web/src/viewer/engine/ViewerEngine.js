import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";
import { RoomEnvironment } from "three/addons/environments/RoomEnvironment.js";

// Направления студийного света (фиксированы, привязка к модели в _anchorStudioRig).
// Ключевой - фронтально-сверху (градиент граней, его тень уходит назад),
// контровой - сзади-сверху (отделение от фона, его тень видна спереди).
const KEY_DIR = new THREE.Vector3(5, 10, 7).normalize();
const RIM_DIR = new THREE.Vector3(-3, 10, -3).normalize();

// Three.js-движок просмотрщика: сцена, загрузка GLB, выбор объектов, подсветка,
// видимость, камера, скриншот. Не знает ни о Vue, ни о SketchUp: наружу -
// события (on/emit). Метаданные объектов экспортёр кладёт в extras.sketchup
// узлов glTF: {persistent_id, entity_type, name, layer}.
export default class ViewerEngine {
  constructor(canvas) {
    this.canvas = canvas;
    this.listeners = new Map();

    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(0xffffff);

    this.camera = new THREE.PerspectiveCamera(45, 1, 0.01, 1000);
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    // Нейтральный tone mapping: держит яркость студийного света в рамках,
    // не сдвигая оттенки материалов (ACES заметно перекрашивает).
    this.renderer.toneMapping = THREE.NeutralToneMapping;
    this.renderer.shadowMap.enabled = true;
    // PCF (не PCFSoft): уважает shadow.radius - мягкий край тени.
    this.renderer.shadowMap.type = THREE.PCFShadowMap;
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));

    this.controls = new OrbitControls(this.camera, this.renderer.domElement);
    this.controls.enableDamping = true;

    // Студийная схема: IBL-окружение ("софтбоксы" RoomEnvironment) даёт
    // мягкую заливку, ключевой свет несёт тень, контровой отделяет модель
    // от белого фона.
    const pmrem = new THREE.PMREMGenerator(this.renderer);
    this.scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
    pmrem.dispose();
    this.scene.environmentIntensity = 0.55;

    this.keyLight = new THREE.DirectionalLight(0xffffff, 1.2);
    this.keyLight.castShadow = true;
    this.keyLight.shadow.mapSize.set(2048, 2048);
    this.keyLight.shadow.radius = 5;
    this.keyLight.shadow.bias = -0.0002;
    this.scene.add(this.keyLight, this.keyLight.target);
    this.rimLight = new THREE.DirectionalLight(0xffffff, 0.6);
    // Тень контрового падает к камере: "лужа" тени видна с любого ракурса.
    this.rimLight.castShadow = true;
    this.rimLight.shadow.mapSize.set(2048, 2048);
    this.rimLight.shadow.radius = 5;
    this.rimLight.shadow.bias = -0.0002;
    this.scene.add(this.rimLight, this.rimLight.target);

    // Невидимый пол (ShadowMaterial прозрачен вне тени) - мягкая тень под
    // моделью, как в предметной съёмке.
    this.ground = new THREE.Mesh(
      new THREE.PlaneGeometry(1, 1),
      new THREE.ShadowMaterial({ opacity: 0.18 })
    );
    this.ground.rotation.x = -Math.PI / 2;
    this.ground.receiveShadow = true;
    this.scene.add(this.ground);

    this.modelRoot = new THREE.Group();
    this.scene.add(this.modelRoot);

    this.modelBox = null;
    this.selectedPid = null;
    this.wireframe = false;
    this.stats = { objects: 0, triangles: 0 };
    this.meshesByPid = new Map(); // pid -> [mesh]
    this.extrasByPid = new Map(); // pid -> extras.sketchup
    this.nodesByPid = new Map(); // pid -> узел-владелец (цель видимости)
    this.originalMaterials = new Map(); // mesh -> материал до подсветки

    this._raf = 0;
    this._disposed = false;
    this._onPointerDown = (e) => this._pickAt(e, false);
    this._onDblClick = (e) => this._pickAt(e, true);
    canvas.addEventListener("pointerdown", this._onPointerDown);
    canvas.addEventListener("dblclick", this._onDblClick);

    const animate = () => {
      if (this._disposed) return;
      this._raf = requestAnimationFrame(animate);
      this.controls.update();
      this.renderer.render(this.scene, this.camera);
    };
    animate();
  }

  dispose() {
    this._disposed = true;
    cancelAnimationFrame(this._raf);
    this.canvas.removeEventListener("pointerdown", this._onPointerDown);
    this.canvas.removeEventListener("dblclick", this._onDblClick);
    this.controls.dispose();
    this.ground.geometry.dispose();
    this.ground.material.dispose();
    this.renderer.dispose();
  }

  // ------------------------------------------------------------- события

  on(event, callback) {
    if (!this.listeners.has(event)) this.listeners.set(event, []);
    this.listeners.get(event).push(callback);
  }

  emit(event, detail) {
    (this.listeners.get(event) || []).forEach((cb) => {
      try {
        cb(detail);
      } catch (err) {
        console.error(`viewer event '${event}' handler failed`, err);
      }
    });
  }

  // -------------------------------------------------------------- модель

  loadModel(url) {
    this.emit("loadStart", { url });
    const loader = new GLTFLoader();
    const finish = (gltf) => {
      this._setHighlight(null);
      this.modelRoot.clear();
      gltf.scene.traverse((obj) => {
        if (obj.isMesh) obj.castShadow = true;
      });
      this.modelRoot.add(gltf.scene);
      this._inheritExtras(this.modelRoot);
      this.modelBox = new THREE.Box3().setFromObject(this.modelRoot);
      this._anchorStudioRig(this.modelBox);
      const triangles = Math.round(this._collectMeshes(this.modelRoot));
      this.stats = { objects: this.meshesByPid.size, triangles };
      this.wireframe = false;
      this.fit();
      this.emit("viewerReady", { url, ...this.stats });
    };
    const fail = (err) => {
      const message = err && err.message ? err.message : String(err);
      console.error("GLB load failed:", err);
      this.emit("loadError", { url, error: message });
    };
    if (/^data:/i.test(url)) {
      // Встроенная модель (single-file HTML): fetch умеет data:-URI даже на file://,
      // где прямой запрос соседнего файла браузер блокирует.
      fetch(url)
        .then((r) => {
          if (!r.ok) throw new Error(`HTTP ${r.status}`);
          return r.arrayBuffer();
        })
        .then((buf) => loader.parse(buf, "", finish, fail))
        .catch(fail);
    } else {
      loader.load(
        url,
        finish,
        (ev) => {
          if (ev && ev.lengthComputable && ev.total > 0) {
            this.emit("progress", { loaded: ev.loaded, total: ev.total });
          }
        },
        fail
      );
    }
  }

  // GLTFLoader кладёт glTF node.extras в node.userData; меши - дети этих узлов.
  // Собираем всю цепочку предков (ближайший владелец первым, внешний инстанс
  // компонента последним), чтобы клик опознал и деталь, и инстанс, в котором
  // она стоит. sketchupOwn помечает узлы, несущие extras (дерево + видимость).
  _inheritExtras(root) {
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

  _collectMeshes(root) {
    this.meshesByPid.clear();
    this.extrasByPid.clear();
    this.nodesByPid.clear();
    let triangles = 0;
    root.traverse((obj) => {
      if (!obj.isMesh) return;
      const geometry = obj.geometry;
      triangles += geometry.index ? geometry.index.count / 3 : geometry.attributes.position.count / 3;
      const chain = obj.userData.sketchupChain || [];
      chain.forEach((sketchup) => {
        const key = String(sketchup.persistent_id);
        if (!this.meshesByPid.has(key)) this.meshesByPid.set(key, []);
        this.meshesByPid.get(key).push(obj);
        this.extrasByPid.set(key, sketchup);
      });
    });
    // Отдельный проход: узлы-владельцы могут не быть мешами.
    root.traverse((obj) => {
      const own = obj.userData && obj.userData.sketchupOwn;
      if (own && own.persistent_id !== undefined) {
        this.nodesByPid.set(String(own.persistent_id), obj);
      }
    });
    return triangles;
  }

  // Скрытые поддеревья не должны выбираться лучом.
  _isShown(object) {
    for (let node = object; node; node = node.parent) {
      if (node.visible === false) return false;
    }
    return true;
  }

  // ------------------------------------------------------------- выбор

  _setHighlight(pid) {
    const had = this.selectedPid;
    this.originalMaterials.forEach((material, mesh) => {
      mesh.material = material;
    });
    this.originalMaterials.clear();
    this.selectedPid = null;
    if (pid === null || pid === undefined) {
      if (had) this.emit("selectionCleared");
      return;
    }
    const meshes = this.meshesByPid.get(String(pid)) || [];
    // Инстансы делят материалы glTF, поэтому подсвечиваем клонами per-mesh.
    meshes.forEach((mesh) => {
      if (!mesh.material) return;
      this.originalMaterials.set(mesh, mesh.material);
      const highlight = mesh.material.clone();
      if (highlight.emissive) {
        highlight.emissive = new THREE.Color(0x3355aa);
        highlight.emissiveIntensity = 0.6;
      }
      mesh.material = highlight;
    });
    if (meshes.length) this.selectedPid = String(pid);
  }

  getObject(pid) {
    const key = String(pid);
    if (!this.meshesByPid.has(key)) return null;
    return this.extrasByPid.get(key) || null;
  }

  // Программный выбор (дерево, window.viewer). Клик по канвасу идёт через
  // _pickAt - он несёт цепочку pid для Ruby.
  selectObject(pid) {
    if (!this.meshesByPid.has(String(pid))) return false;
    this._setHighlight(pid);
    this.emit("objectSelected", { pid: String(pid), extras: this.getObject(pid), chain: null });
    return true;
  }

  clearSelection() {
    this._setHighlight(null);
  }

  focusObject(pid) {
    const meshes = this.meshesByPid.get(String(pid));
    if (!meshes || meshes.length === 0) return false;
    const box = new THREE.Box3();
    meshes.forEach((mesh) => box.expandByObject(mesh));
    if (box.isEmpty()) return false;
    this._fitTo(box);
    return true;
  }

  // Видимость объекта на стороне viewer'а; сам GLB не меняется.
  setShowObject(pid, visible) {
    const node = this.nodesByPid.get(String(pid));
    if (!node) return false;
    node.visible = !!visible;
    this.emit("objectVisibilityChanged", { pid: String(pid), visible: !!visible });
    return true;
  }

  isVisible(pid) {
    const node = this.nodesByPid.get(String(pid));
    return node ? node.visible !== false : true;
  }

  toggleWireframe() {
    this.wireframe = !this.wireframe;
    this.modelRoot.traverse((obj) => {
      if (obj.isMesh && obj.material) obj.material.wireframe = this.wireframe;
    });
    this.emit("wireframe", this.wireframe);
    return this.wireframe;
  }

  // ------------------------------------------------------- студийный свет

  // Привязывает свет и пол к габариту загруженной модели: направления
  // фиксированы (KEY_DIR/RIM_DIR), позиция и shadow-frustum подгоняются
  // под центр и радиус, чтобы тень не обрезалась на любых масштабах.
  _anchorStudioRig(box) {
    const center = box.getCenter(new THREE.Vector3());
    const radius = Math.max(box.getBoundingSphere(new THREE.Sphere()).radius, 0.001);
    const dist = radius * 4;
    this.keyLight.position.copy(center).addScaledVector(KEY_DIR, dist);
    this.keyLight.target.position.copy(center);
    this.rimLight.position.copy(center).addScaledVector(RIM_DIR, dist);
    this.rimLight.target.position.copy(center);

    const size = box.getSize(new THREE.Vector3());
    const footprint = Math.max(size.x, size.z, radius);
    this.ground.position.set(center.x, box.min.y - radius * 0.002, center.z);
    this.ground.scale.set(footprint * 2.5, footprint * 2.5, 1);

    // Одинаковый frustum у обоих источников: покрывает модель и запас вниз
    // до пола, куда падает тень.
    for (const light of [this.keyLight, this.rimLight]) {
      const cam = light.shadow.camera;
      cam.left = -radius * 1.5;
      cam.right = radius * 1.5;
      cam.top = radius * 1.5;
      cam.bottom = -radius * 1.5;
      cam.near = Math.max(dist - radius * 2, 0.01);
      cam.far = dist + radius * 3; // запас вниз до пола
      cam.updateProjectionMatrix();
      // normalBias в мировых единицах: масштабируем от радиуса модели.
      light.shadow.normalBias = radius * 0.01;
    }
  }

  // ------------------------------------------------------------- камера

  _fitTo(box) {
    const sphere = box.getBoundingSphere(new THREE.Sphere());
    const center = sphere.center.clone();
    const radius = Math.max(sphere.radius, 0.001);
    const dist = radius / Math.sin(THREE.MathUtils.degToRad(this.camera.fov / 2));
    this.camera.position.copy(center).addScaledVector(new THREE.Vector3(1, 0.8, 1).normalize(), dist);
    this.camera.near = radius / 100;
    this.camera.far = dist * 10;
    this.camera.updateProjectionMatrix();
    this.controls.target.copy(center);
    this.controls.update();
  }

  fit() {
    if (this.modelBox) this._fitTo(this.modelBox);
  }

  reset() {
    this.fit();
  }

  // ------------------------------------------------------- данные для UI

  // Плоское дерево узлов с identity: {pid, name, type, children}.
  getTree() {
    const convert = (parent) => {
      const out = [];
      for (const child of parent.children) {
        const own = child.userData && child.userData.sketchupOwn;
        if (!own || own.persistent_id === undefined) {
          // Обёртка без identity (например группа сцены glTF): содержимое
          // поднимается на уровень выше.
          if (child.children.length) out.push(...convert(child));
          continue;
        }
        out.push({
          pid: String(own.persistent_id),
          name: (own.name && own.name.trim()) || own.entity_type || "Объект",
          type: own.entity_type || "",
          children: convert(child),
        });
      }
      return out;
    };
    return convert(this.modelRoot);
  }

  resize() {
    const w = this.canvas.clientWidth || window.innerWidth;
    const h = this.canvas.clientHeight || window.innerHeight;
    this.renderer.setSize(w, h, false);
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
  }

  // Кадр на момент вызова; PNG-блоб. Не полагается на preserveDrawingBuffer:
  // рендерим непосредственно перед снятием.
  screenshot() {
    this.renderer.render(this.scene, this.camera);
    return new Promise((resolve, reject) => {
      this.canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new Error("toBlob failed"))), "image/png");
    });
  }

  // --------------------------------------------------------------- пикинг

  _pickAt(e, isDoubleClick) {
    const rect = this.canvas.getBoundingClientRect();
    const pointer = new THREE.Vector2(
      ((e.clientX - rect.left) / rect.width) * 2 - 1,
      -((e.clientY - rect.top) / rect.height) * 2 + 1
    );
    const raycaster = new THREE.Raycaster();
    raycaster.setFromCamera(pointer, this.camera);
    const hits = raycaster.intersectObjects(this.modelRoot.children, true);
    const hit = hits.find((h) => h.object.isMesh && this._isShown(h.object)) || null;
    const chain = (hit && hit.object.userData && hit.object.userData.sketchupChain) || [];
    if (!chain.length) {
      if (!isDoubleClick) this.clearSelection();
      return;
    }
    // Опознаём внешний объект (инстанс компонента), а Ruby отправляем всю
    // цепочку: он выберет первый pid, существующий как entity в модели.
    const outermost = chain[chain.length - 1];
    const chainPids = chain.map((sketchup) => String(sketchup.persistent_id));
    this._setHighlight(outermost.persistent_id);
    this.emit("objectSelected", {
      pid: String(outermost.persistent_id),
      extras: this.getObject(outermost.persistent_id),
      chain: chainPids,
    });
    if (isDoubleClick) this.focusObject(outermost.persistent_id);
  }
}

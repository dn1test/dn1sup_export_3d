import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";

// Направления студийного света (фиксированы, привязка к модели в _anchorStudioRig).
// Классическая схема предметной съёмки из четырёх источников разной силы:
// ключевой - фронтально-сверху, самый яркий (градиент граней, основной блик,
// его тень уходит назад); контровой - сзади-сверху, вдвое слабее (отделение
// от фона, его тень видна спереди); заполняющий - слева-снизу без тени,
// втрое слабее ключевого (поднимает теневую сторону); верхний - мягкий
// вертикальный, даёт горизонтальным граням отдельный диапазон яркости.
const KEY_DIR = new THREE.Vector3(5, 10, 7).normalize();
const RIM_DIR = new THREE.Vector3(-3, 10, -3).normalize();
const FILL_DIR = new THREE.Vector3(-6, 3, 6).normalize();
const TOP_DIR = new THREE.Vector3(0.5, 10, -0.5).normalize();

// "Фотографическая" обработка материалов. SketchUp не хранит PBR-данных:
// экспортёр пишет всем материалам нейтральные roughness 0.9 / metallic 0.0,
// и любая поверхность выглядит одинаково мертво - без бликов и отражений.
// Вьюер работает как фотостудия: поверх нейтрального GLB подбирает отделку
// по имени материала (рус./англ., фамилии из мебельных библиотек). Металл
// становится отражающим, стекло - прозрачным с резким бликом, остальное
// уходит в мягкую матовую зону, где видны широкие блики ключевого света
// и размытые отражения окружения. GLB не меняется: это слой подачи, а не
// данных; авторские PBR-значения (не нейтральная сигнатура) не трогаем.
const MATERIAL_FAMILIES = [
  { pattern: /зерк|mirror/i, roughness: 0.05, metallic: 1.0, envMapIntensity: 1.6 },
  { pattern: /хром|chrome|никел|nickel/i, roughness: 0.12, metallic: 1.0, envMapIntensity: 1.5 },
  { pattern: /glass|стекл|оргстекл|плексигл|плекс|акрил/i, roughness: 0.08, metallic: 0.0, envMapIntensity: 1.4, opacity: 0.35 },
  { pattern: /метал|metal|сталь|steel|нерж|алюм|alum|латун|brass|бронз|bronze/i, roughness: 0.35, metallic: 1.0, envMapIntensity: 1.3 },
  { pattern: /глян|gloss|лак|lacquer|эмаль|enamel|краск|paint|mdf/i, roughness: 0.32, metallic: 0.0, envMapIntensity: 1.15 },
  { pattern: /столешн|countertop|камен|stone|мрамор|marble|бетон|beton|concrete/i, roughness: 0.45, metallic: 0.0, envMapIntensity: 1.1 },
];
const DEFAULT_FINISH = { roughness: 0.6, metallic: 0.0, envMapIntensity: 1.0 };

// Интенсивности студийного света по умолчанию (значения держат освещённую
// грань близкой к альбедо материала). Доступны пользователю на вкладке «Вид».
const DEFAULT_LIGHTING = { key: 1.0, rim: 0.55, fill: 0.3, top: 0.22, env: 0.5, background: 1.0 };

// Three.js-движок просмотрщика: сцена, загрузка GLB, выбор объектов, подсветка,
// видимость, камера, скриншот. Не знает ни о Vue, ни о SketchUp: наружу -
// события (on/emit). Метаданные объектов экспортёр кладёт в extras.sketchup
// узлов glTF: {persistent_id, entity_type, name, layer}.
export default class ViewerEngine {
  constructor(canvas) {
    this.canvas = canvas;
    this.listeners = new Map();

    this.scene = new THREE.Scene();
    // Фон - светлосерая "циклорама" (текстура кэшируется: режим «Рисованное»
    // подменяет её белым цветом, «Фото» возвращает). Серый отделяет от фона
    // даже белые модели.
    this._cycloramaTexture = this._makeCycloramaBackground();
    // Презентация: режим отображения, качество подачи материалов и
    // интенсивности источников (управляются вкладкой «Вид» вьюера).
    this.presentation = { mode: "photo", quality: "high", lighting: { ...DEFAULT_LIGHTING } };

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

    // Студийная схема. IBL - собственная "сфера-софтбоксы" (см.
    // _makeStudioEnvironment): ленты света размещены под ракурсом камеры по
    // умолчанию и контрового света, поэтому фасады ловят вертикальные блики,
    // а столешницы - отражение сзади-сверху. Ключевой свет несёт тень и
    // зеркальный блик, контровой отделяет модель от фона. Суммарная энергия
    // удерживает освещённую грань близкой к альбедо материала.
    const pmrem = new THREE.PMREMGenerator(this.renderer);
    this.scene.environment = pmrem.fromScene(this._makeStudioEnvironment(), 0.04).texture;
    pmrem.dispose();

    this.keyLight = new THREE.DirectionalLight(0xffffff, 1.0);
    this.keyLight.castShadow = true;
    this.keyLight.shadow.mapSize.set(2048, 2048);
    this.keyLight.shadow.radius = 6;
    this.keyLight.shadow.bias = -0.0002;
    this.scene.add(this.keyLight, this.keyLight.target);
    this.rimLight = new THREE.DirectionalLight(0xffffff, 0.55);
    // Тень контрового падает к камере: "лужа" тени видна с любого ракурса.
    this.rimLight.castShadow = true;
    this.rimLight.shadow.mapSize.set(2048, 2048);
    this.rimLight.shadow.radius = 6;
    this.rimLight.shadow.bias = -0.0002;
    this.scene.add(this.rimLight, this.rimLight.target);
    this.fillLight = new THREE.DirectionalLight(0xffffff, 0.3);
    this.scene.add(this.fillLight, this.fillLight.target);
    this.topLight = new THREE.DirectionalLight(0xffffff, 0.22);
    this.scene.add(this.topLight, this.topLight.target);

    // Невидимый пол (ShadowMaterial прозрачен вне тени) - мягкая тень под
    // моделью, как в предметной съёмке.
    this.ground = new THREE.Mesh(
      new THREE.PlaneGeometry(1, 1),
      new THREE.ShadowMaterial({ opacity: 0.22 })
    );
    this.ground.rotation.x = -Math.PI / 2;
    this.ground.receiveShadow = true;
    this.scene.add(this.ground);

    // Ровная заливка для режима «Рисованное»: материал показывает чистое
    // альбедо, как грани в SketchUp.
    this.ambientLight = new THREE.AmbientLight(0xffffff, 0);
    this.scene.add(this.ambientLight);
    this._applyLighting();

    this.modelRoot = new THREE.Group();
    this.scene.add(this.modelRoot);

    this.modelBox = null;
    this.selectedPid = null;
    // Мультивыборка (синхронизация с выделением SketchUp в диалоге экспорта);
    // selectedPid остаётся первым выбранным - на нём держится дерево/инфо.
    this.selectedPids = new Set();
    this.wireframe = false;
    // Контурные линии рёбер включены по умолчанию (вид как в SketchUp).
    this.edgesVisible = true;
    // Общий материал всех контуров: тонкая тёмная линия. LineBasicMaterial
    // в WebGL всегда рисуется толщиной 1px (linewidth игнорируется), что и
    // даёт нужную "тонкость"; toneMapped:false держит цвет постоянным.
    this.edgeMaterial = new THREE.LineBasicMaterial({ color: 0x3c4046, toneMapped: false });
    // Кэш EdgesGeometry по исходной геометрии: инстансы одного компонента
    // делят её в glTF, расчёт контуров выполняется один раз (AGENTS.md #25).
    this._edgeCache = new Map();
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
    this._edgeCache.forEach((geometry) => geometry.dispose());
    this._edgeCache.clear();
    this.edgeMaterial.dispose();
    this._cycloramaTexture.dispose();
    if (this.scene.environment && this.scene.environment.dispose) this.scene.environment.dispose();
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
      this._applyHighlight(null);
      // Контры прошлой модели ссылаются на её геометрию - освобождаем кэш.
      this._edgeCache.forEach((geometry) => geometry.dispose());
      this._edgeCache.clear();
      this.modelRoot.clear();
      gltf.scene.traverse((obj) => {
        if (obj.isMesh) obj.castShadow = true;
      });
      this._tuneMaterials(gltf.scene);
      this._addEdges(gltf.scene);
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

  // Подсветка набора pid. Инстансы делят материалы glTF, поэтому
  // подсвечиваем клонами per-mesh; повторные меши (пересечение pid) один.
  _applyHighlight(pids) {
    const had = this.selectedPids.size > 0;
    this.originalMaterials.forEach((material, mesh) => {
      mesh.material = material;
    });
    this.originalMaterials.clear();
    this.selectedPids = new Set();
    this.selectedPid = null;
    if (!pids || pids.length === 0) {
      if (had) this.emit("selectionCleared");
      return;
    }
    const seen = new Set();
    pids.forEach((pid) => {
      const key = String(pid);
      (this.meshesByPid.get(key) || []).forEach((mesh) => {
        if (seen.has(mesh) || !mesh.material) return;
        seen.add(mesh);
        this.originalMaterials.set(mesh, mesh.material);
        const highlight = mesh.material.clone();
        if (highlight.emissive) {
          highlight.emissive = new THREE.Color(0x3355aa);
          highlight.emissiveIntensity = 0.6;
        }
        mesh.material = highlight;
      });
      if (this.meshesByPid.has(key)) this.selectedPids.add(key);
    });
    this.selectedPid = this.selectedPids.values().next().value || null;
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
    this._applyHighlight([pid]);
    this.emit("objectSelected", { pid: String(pid), extras: this.getObject(pid), chain: null });
    return true;
  }

  // Мультивыборка извне (выделение SketchUp в диалоге экспорта). Нарочно не
  // эмитит objectSelected: это событие про клик пользователя, а обратное
  // событие превратило бы синхронизацию в петлю Ruby -> JS -> Ruby.
  setSelection(pids) {
    const list = (pids || []).map(String).filter((pid) => this.meshesByPid.has(pid));
    this._applyHighlight(list);
    return this.selectedPids.size;
  }

  clearSelection() {
    this._applyHighlight(null);
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

  // ------------------------------------------------------- контурные линии

  // Тонкие контуры рёбер у каждого меша (вид как в SketchUp). Порог 30°
  // прячет диагонали триангуляции (угол копланарных треугольников 0°),
  // оставляя реальные изломы формы. Контур - ребёнок меша: наследует
  // трансформацию и скрывается вместе с объектом из дерева.
  _addEdges(root) {
    root.traverse((obj) => {
      if (!obj.isMesh) return;
      // Поверхность чуть сдвигается вглубь буфера глубины, иначе контур,
      // лежащий ровно на грани, мерцает (z-fighting).
      const materials = Array.isArray(obj.material) ? obj.material : [obj.material];
      materials.forEach((m) => {
        if (!m) return;
        m.polygonOffset = true;
        m.polygonOffsetFactor = 1;
        m.polygonOffsetUnits = 1;
      });
      const edges = new THREE.LineSegments(this._edgeGeometryFor(obj.geometry), this.edgeMaterial);
      edges.userData.isEdge = true;
      // Иначе Raycaster ловит Line с порогом в мировых единицах и клики
      // "залипали" бы на контуре вместо меша.
      edges.raycast = () => {};
      edges.visible = this.edgesVisible;
      obj.add(edges);
    });
  }

  // Инстансы одного компонента делят геометрию: расчёт контура - один раз.
  _edgeGeometryFor(geometry) {
    let edges = this._edgeCache.get(geometry.uuid);
    if (!edges) {
      edges = new THREE.EdgesGeometry(geometry, 30);
      this._edgeCache.set(geometry.uuid, edges);
    }
    return edges;
  }

  toggleEdges() {
    this.edgesVisible = !this.edgesVisible;
    this.modelRoot.traverse((obj) => {
      if (obj.userData && obj.userData.isEdge) obj.visible = this.edgesVisible;
    });
    this.emit("edges", this.edgesVisible);
    return this.edgesVisible;
  }

  // ------------------------------------------------- презентация материалов

  // Запоминает исходные PBR-значения материала (как в GLB) в userData и
  // применяет текущий уровень качества подачи. Правим только нейтральную
  // сигнатуру экспортёра (roughness 0.9 / metallic 0): если в GLB есть
  // авторские PBR-значения, они остаются как есть.
  _tuneMaterials(root) {
    const seen = new Set();
    this._tunedMaterials = [];
    root.traverse((obj) => {
      if (!obj.isMesh || !obj.material) return;
      const materials = Array.isArray(obj.material) ? obj.material : [obj.material];
      materials.forEach((material) => {
        if (seen.has(material.uuid)) return;
        seen.add(material.uuid);
        if (!material.isMeshStandardMaterial && !material.isMeshPhysicalMaterial) return;
        material.userData.sketchupBase = {
          roughness: material.roughness,
          metalness: material.metalness,
          envMapIntensity: material.envMapIntensity,
          opacity: material.opacity,
          transparent: material.transparent,
        };
        this._tunedMaterials.push(material);
      });
    });
    this._applyQuality();
  }

  // Уровни подачи (действуют в режиме «Фото»):
  // high   - подбор отделки по имени материала (см. MATERIAL_FAMILIES):
  //          металл отражающий, стекло прозрачное, остальное матовое;
  // medium - единая матовая отделка без персональных отражений;
  // low    - плоские цвета без PBR (roughness 1, без отражений).
  // Принудительная прозрачность стекла - на high и medium: это свойство
  // материала, а не качество; авторская прозрачность GLB (alphaMode BLEND)
  // сохраняется на всех уровнях.
  _applyQuality() {
    const { quality, mode } = this.presentation;
    const sketch = mode === "sketch";
    (this._tunedMaterials || []).forEach((material) => {
      const base = material.userData.sketchupBase;
      material.roughness = base.roughness;
      material.metalness = base.metalness;
      material.envMapIntensity = base.envMapIntensity;
      material.opacity = base.opacity;
      material.transparent = base.transparent;
      const neutral = Math.abs(base.roughness - 0.9) < 0.01 && base.metalness < 0.01;
      if (sketch) {
        // Металлы без окружения чёрные (нет диффузной составляющей): в
        // «рисованном» режиме показываем альбедо материала.
        material.metalness = 0;
        material.envMapIntensity = 0;
        return;
      }
      if (quality === "low") {
        if (neutral) {
          material.roughness = 1.0;
          material.envMapIntensity = 0;
        }
        return;
      }
      if (!neutral) return;
      const name = material.name || "";
      const family = quality === "high"
        ? MATERIAL_FAMILIES.find((f) => f.pattern.test(name)) || DEFAULT_FINISH
        : { ...DEFAULT_FINISH, envMapIntensity: 0.9 };
      material.roughness = family.roughness;
      material.metalness = family.metallic;
      material.envMapIntensity = family.envMapIntensity;
      if (family.opacity && material.opacity > 0.85) {
        material.transparent = true;
        material.opacity = family.opacity;
      }
    });
  }

  setQuality(level) {
    if (!["high", "medium", "low"].includes(level) || level === this.presentation.quality) {
      return this.presentation.quality;
    }
    this.presentation.quality = level;
    this._applyQuality();
    this.emit("quality", level);
    return level;
  }

  // ------------------------------------------------------- студийный свет

  // Приводит свет, фон и тени к текущему режиму презентации. «Фото» -
  // студийная схема из четырёх источников + IBL-окружение + серая
  // циклорама; «Рисованное» - ровная заливка (чистое альбедо, как грани
  // в SketchUp), белый фон, без теней; контуры рёбер остаются в обоих
  // режимах (их прячет отдельный переключатель).
  _applyLighting() {
    const { lighting, mode } = this.presentation;
    const photo = mode === "photo";
    this.keyLight.intensity = photo ? lighting.key : 0;
    this.rimLight.intensity = photo ? lighting.rim : 0;
    this.fillLight.intensity = photo ? lighting.fill : 0;
    this.topLight.intensity = photo ? lighting.top : 0;
    this.ambientLight.intensity = photo ? 0 : 1;
    this.scene.environmentIntensity = photo ? lighting.env : 0;
    this.scene.background = photo ? this._cycloramaTexture : new THREE.Color(0xffffff);
    this.scene.backgroundIntensity = lighting.background;
    this.ground.visible = photo;
  }

  setMode(mode) {
    if (!["photo", "sketch"].includes(mode) || mode === this.presentation.mode) {
      return this.presentation.mode;
    }
    this.presentation.mode = mode;
    this._applyQuality();
    this._applyLighting();
    this.emit("mode", mode);
    return mode;
  }

  // Частичное обновление интенсивностей: setLighting({ key: 1.3, env: 0.6 }).
  // В режиме «Рисованное» значения запоминаются, но не применяются.
  setLighting(partial) {
    const lighting = this.presentation.lighting;
    Object.entries(partial || {}).forEach(([name, value]) => {
      if (name in lighting && Number.isFinite(+value)) lighting[name] = Math.max(0, +value);
    });
    if (this.presentation.mode === "photo") this._applyLighting();
    this.emit("lighting", { ...lighting });
    return { ...lighting };
  }

  // Возвращает интенсивности света к значениям по умолчанию.
  resetLighting() {
    this.presentation.lighting = { ...DEFAULT_LIGHTING };
    if (this.presentation.mode === "photo") this._applyLighting();
    this.emit("lighting", { ...this.presentation.lighting });
    return { ...this.presentation.lighting };
  }

  // Снимок настроек презентации для инициализации UI.
  getPresentation() {
    return {
      mode: this.presentation.mode,
      quality: this.presentation.quality,
      lighting: { ...this.presentation.lighting },
    };
  }

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
    this.fillLight.position.copy(center).addScaledVector(FILL_DIR, dist);
    this.fillLight.target.position.copy(center);
    this.topLight.position.copy(center).addScaledVector(TOP_DIR, dist);
    this.topLight.target.position.copy(center);

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

  // Студийная "сфера" для PMREM. Стены - серые, низ - белый "пол
  // циклорамы" с плавным переходом: фасад, обращённый к камере, зеркалит
  // направление назад-вниз и ловит светлый низ - получается фирменный
  // градиент предметной съёмки (низ фасада светлее) с любого ракурса.
  // Ленты-софтбоксы: главная - со стороны камеры по умолчанию (45°),
  // контровая совпадает с RIM_DIR (225°) и читается в столешницах,
  // потолок выравнивает верхние грани, боковые не дают металлу чернеть.
  _makeStudioEnvironment() {
    const scene = new THREE.Scene();
    const shell = new THREE.Mesh(
      new THREE.SphereGeometry(20, 32, 24),
      new THREE.MeshBasicMaterial({ side: THREE.BackSide, vertexColors: true })
    );
    const position = shell.geometry.getAttribute("position");
    const colors = [];
    const wall = new THREE.Color(0xb9bbc0);
    const floor = new THREE.Color(0xd9dadc);
    const vertex = new THREE.Vector3();
    const mixed = new THREE.Color();
    for (let i = 0; i < position.count; i++) {
      vertex.fromBufferAttribute(position, i);
      // Нормированная высота вершины: -1 (пол) .. +1 (зенит). Переход
      // пола в стену размазан чуть выше горизонта, чтобы стык не был виден.
      const t = THREE.MathUtils.clamp((vertex.y / 20 + 0.05) / 0.3, 0, 1);
      mixed.copy(floor).lerp(wall, t);
      colors.push(mixed.r, mixed.g, mixed.b);
    }
    shell.geometry.setAttribute("color", new THREE.Float32BufferAttribute(colors, 3));
    scene.add(shell);
    const strip = (azDeg, elevDeg, intensity, width, height) => {
      const az = THREE.MathUtils.degToRad(azDeg);
      const elev = THREE.MathUtils.degToRad(elevDeg);
      const radius = 19;
      const mesh = new THREE.Mesh(
        new THREE.PlaneGeometry(width, height),
        new THREE.MeshBasicMaterial({ color: new THREE.Color(1, 1, 1).multiplyScalar(intensity) })
      );
      mesh.position.set(
        Math.cos(az) * Math.cos(elev) * radius,
        Math.sin(elev) * radius,
        Math.sin(az) * Math.cos(elev) * radius
      );
      mesh.lookAt(0, 0, 0);
      scene.add(mesh);
    };
    strip(45, 18, 12, 14, 7);
    strip(225, 20, 6, 14, 8);
    strip(-40, 20, 3.5, 10, 5);
    strip(130, 20, 3.5, 10, 5);
    strip(45, 90, 12, 8, 8);
    return scene;
  }

  // Светлосерая "циклорама": серый градиент чуть светлее к зениту и темнее
  // к полу, как бесшовный студийный фон. Canvas 2x512 достаточно: фон
  // растягивается на весь кадр без деталей.
  _makeCycloramaBackground() {
    const canvas = document.createElement("canvas");
    canvas.width = 2;
    canvas.height = 512;
    const ctx = canvas.getContext("2d");
    const gradient = ctx.createLinearGradient(0, 0, 0, 512);
    gradient.addColorStop(0, "#dfe0e3");
    gradient.addColorStop(0.45, "#d4d5d9");
    gradient.addColorStop(1, "#c2c4c9");
    ctx.fillStyle = gradient;
    ctx.fillRect(0, 0, 2, 512);
    const texture = new THREE.CanvasTexture(canvas);
    texture.colorSpace = THREE.SRGBColorSpace;
    return texture;
  }

  // ------------------------------------------------------------- камера

  _fitTo(box) {
    const sphere = box.getBoundingSphere(new THREE.Sphere());
    const center = sphere.center.clone();
    const radius = Math.max(sphere.radius, 0.001);
    const dist = radius / Math.sin(THREE.MathUtils.degToRad(this.camera.fov / 2));
    // Ракурс чуть сверху (как в предметной съёмке): виден верх изделия и
    // блик ключевого света на горизонтальных гранях.
    this.camera.position.copy(center).addScaledVector(new THREE.Vector3(1, 1.0, 1).normalize(), dist);
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
    this._applyHighlight([outermost.persistent_id]);
    this.emit("objectSelected", {
      pid: String(outermost.persistent_id),
      extras: this.getObject(outermost.persistent_id),
      chain: chainPids,
    });
    if (isDoubleClick) this.focusObject(outermost.persistent_id);
  }
}

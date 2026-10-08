// Export dialog front-end. Talks to Ruby (Dn1supExport3d::ExportDialog)
// through the HtmlDialog bridge: window.sketchup.* for JS -> Ruby,
// window.exporter.* for Ruby -> JS. All model-derived strings are rendered
// via textContent / value only - never innerHTML (AGENTS.md #24).
(function () {
  "use strict";

  var $ = function (id) { return document.getElementById(id); };
  var bridge = window.sketchup; // injected by HtmlDialog; absent in browsers

  function call(name) {
    if (!bridge || typeof bridge[name] !== "function") return;
    bridge[name].apply(bridge, Array.prototype.slice.call(arguments, 1));
  }

  window.exporter = {
    // Ruby -> JS
    setOutputPath: function (path) {
      $("path").value = path;
    },
    receiveState: function (state) {
      window.__lastState = state;
      render(state);
    },
  };

  function collectOptions() {
    var scope = document.querySelector('input[name="scope"]:checked');
    return {
      scope: scope ? scope.value : "all",
      path: $("path").value,
      include_hidden: $("include-hidden").checked,
    };
  }

  function setStatus(kind, message) {
    var status = $("status");
    if (!message) {
      status.className = "hidden";
      status.textContent = "";
      return;
    }
    status.className = kind;
    status.textContent = message;
  }

  function render(state) {
    state = state || {};
    var exporting = state.mode === "exporting";
    var done = state.mode === "done";

    if (typeof state.selection_count === "number") {
      $("sel-count").textContent = "(" + state.selection_count + ")";
    }
    if (state.default_path && !$("path").value) {
      $("path").value = state.default_path;
    }

    $("btn-export").disabled = exporting;
    $("btn-browse").disabled = exporting;
    $("progress").className = exporting ? "" : "hidden";

    if (state.mode === "error") {
      setStatus("error", state.message || "Export failed.");
    } else if (exporting) {
      setStatus("info", "Export is running. SketchUp may be unresponsive for a moment on large models.");
    } else {
      setStatus(null, null);
    }

    var results = $("results");
    if (done && state.stats) {
      var s = state.stats;
      results.className = "";
      $("stats").textContent =
        s.faces + " faces (" + s.triangles + " triangles), " +
        s.materials + " materials, " + s.textures + " textures\n" +
        formatBytes(s.bytes) + " in " + s.seconds + " s\n" +
        s.path;
      if (state.web_dir_name) {
        $("btn-viewer").disabled = false;
        $("btn-folder").disabled = false;
      }
    } else {
      results.className = "hidden";
      $("btn-viewer").disabled = true;
      $("btn-folder").disabled = true;
    }
  }

  function formatBytes(bytes) {
    if (bytes >= 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + " MB";
    if (bytes >= 1024) return (bytes / 1024).toFixed(1) + " KB";
    return bytes + " B";
  }

  $("btn-browse").onclick = function () { call("browse_output", $("path").value); };
  $("btn-export").onclick = function () { call("export_start", JSON.stringify(collectOptions())); };
  $("btn-cancel").onclick = function () { call("cancel"); };
  $("btn-viewer").onclick = function () { call("open_viewer"); };
  $("btn-folder").onclick = function () { call("open_folder"); };

  // Tell Ruby the page is alive so it can push the initial state
  // (execute_script before load would be lost).
  call("dialog_ready");
})();

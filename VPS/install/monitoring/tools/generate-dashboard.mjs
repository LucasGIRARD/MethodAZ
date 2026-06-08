import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const output = path.resolve(here, "../grafana/dashboards/vps-observability.json");

const prometheus = { type: "prometheus", uid: "prometheus" };
const loki = { type: "loki", uid: "loki" };

let nextId = 1;

function target(expr, legendFormat = "", refId = "A", datasource = prometheus) {
  return {
    datasource,
    editorMode: "code",
    expr,
    legendFormat,
    range: true,
    refId,
  };
}

function basePanel(title, type, x, y, w, h, datasource = prometheus) {
  return {
    id: nextId++,
    title,
    type,
    datasource,
    gridPos: { x, y, w, h },
    fieldConfig: {
      defaults: {
        color: { mode: "palette-classic" },
        custom: {},
        mappings: [],
        thresholds: {
          mode: "absolute",
          steps: [
            { color: "green", value: null },
            { color: "red", value: 80 },
          ],
        },
      },
      overrides: [],
    },
    options: {},
    targets: [],
  };
}

function row(title, y, collapsed = false, panels = []) {
  const panel = basePanel(title, "row", 0, y, 24, 1);
  panel.collapsed = collapsed;
  panel.panels = panels;
  return panel;
}

function stat(title, expr, x, y, w = 3, unit = "short", options = {}) {
  const panel = basePanel(title, "stat", x, y, w, 4);
  panel.targets = [target(expr)];
  panel.fieldConfig.defaults.unit = unit;
  panel.fieldConfig.defaults.noValue = "Indisponible";
  panel.options = {
    colorMode: "value",
    graphMode: "area",
    justifyMode: "auto",
    orientation: "auto",
    reduceOptions: {
      calcs: ["lastNotNull"],
      fields: "",
      values: false,
    },
    textMode: "auto",
    wideLayout: true,
  };
  Object.assign(panel.fieldConfig.defaults, options.fieldDefaults ?? {});
  return panel;
}

function timeseries(title, targets, x, y, w = 12, h = 8, unit = "short") {
  const panel = basePanel(title, "timeseries", x, y, w, h);
  panel.targets = targets;
  panel.fieldConfig.defaults.unit = unit;
  panel.fieldConfig.defaults.custom = {
    axisCenteredZero: false,
    axisColorMode: "text",
    axisLabel: "",
    axisPlacement: "auto",
    barAlignment: 0,
    drawStyle: "line",
    fillOpacity: 12,
    gradientMode: "none",
    hideFrom: { legend: false, tooltip: false, viz: false },
    lineInterpolation: "linear",
    lineWidth: 1,
    pointSize: 4,
    scaleDistribution: { type: "linear" },
    showPoints: "never",
    spanNulls: false,
    stacking: { group: "A", mode: "none" },
    thresholdsStyle: { mode: "off" },
  };
  panel.options = {
    legend: {
      calcs: ["lastNotNull", "max"],
      displayMode: "table",
      placement: "bottom",
      showLegend: true,
    },
    tooltip: { mode: "multi", sort: "desc" },
  };
  return panel;
}

function gauge(title, expr, x, y, w = 6, unit = "percent") {
  const panel = basePanel(title, "gauge", x, y, w, 5);
  panel.targets = [target(expr)];
  panel.fieldConfig.defaults.min = 0;
  panel.fieldConfig.defaults.max = 100;
  panel.fieldConfig.defaults.unit = unit;
  panel.fieldConfig.defaults.noValue = "Indisponible";
  panel.options = {
    orientation: "auto",
    reduceOptions: { calcs: ["lastNotNull"], fields: "", values: false },
    showThresholdLabels: false,
    showThresholdMarkers: true,
    sizing: "auto",
  };
  return panel;
}

function textPanel(title, markdown, x, y, w = 24, h = 3) {
  const panel = basePanel(title, "text", x, y, w, h, null);
  panel.options = { content: markdown, mode: "markdown" };
  return panel;
}

function logsPanel(title, expr, x, y, w = 24, h = 10) {
  const panel = basePanel(title, "logs", x, y, w, h, loki);
  panel.targets = [
    {
      datasource: loki,
      editorMode: "code",
      expr,
      queryType: "range",
      refId: "A",
    },
  ];
  panel.options = {
    dedupStrategy: "none",
    enableLogDetails: true,
    prettifyLogMessage: false,
    showCommonLabels: false,
    showLabels: false,
    showTime: true,
    sortOrder: "Descending",
    wrapLogMessage: true,
  };
  return panel;
}

const panels = [];

panels.push(row("Vue d'ensemble", 0));
panels.push(stat("Hôte joignable", 'up{job="node",instance=~"$instance"}', 0, 1));
panels.push(stat("Docker joignable", 'up{job="docker"}', 3, 1));
panels.push(stat("cAdvisor joignable (optionnel)", 'up{job="cadvisor"}', 6, 1));
panels.push(stat("Conteneurs actifs", "vps_docker_containers_running", 9, 1));
panels.push(stat("CPU utilisé", '100 - (avg(rate(node_cpu_seconds_total{job="node",instance=~"$instance",mode="idle"}[$__rate_interval])) * 100)', 12, 1, 3, "percent"));
panels.push(stat("Mémoire utilisée", '100 * (1 - node_memory_MemAvailable_bytes{job="node",instance=~"$instance"} / node_memory_MemTotal_bytes{job="node",instance=~"$instance"})', 15, 1, 3, "percent"));
panels.push(stat("Racine utilisée", '100 * (1 - node_filesystem_avail_bytes{job="node",instance=~"$instance",mountpoint="/",fstype!~"tmpfs|overlay"} / node_filesystem_size_bytes{job="node",instance=~"$instance",mountpoint="/",fstype!~"tmpfs|overlay"})', 18, 1, 3, "percent"));
panels.push(stat("Journaux Grafana", "vps_logs_enabled", 21, 1, 3, "bool", {
  fieldDefaults: {
    mappings: [
      {
        options: {
          "0": { color: "gray", index: 0, text: "Désactivés" },
          "1": { color: "green", index: 1, text: "Activés" },
        },
        type: "value",
      },
    ],
  },
}));

panels.push(row("Système Debian et partition racine", 5));
panels.push(timeseries("Utilisation CPU", [
  target('100 - (avg by (instance) (rate(node_cpu_seconds_total{job="node",instance=~"$instance",mode="idle"}[$__rate_interval])) * 100)', "CPU"),
  target('avg by (instance) (rate(node_cpu_seconds_total{job="node",instance=~"$instance",mode="iowait"}[$__rate_interval])) * 100', "Attente E/S", "B"),
], 0, 6, 12, 8, "percent"));
panels.push(timeseries("Mémoire", [
  target('node_memory_MemTotal_bytes{job="node",instance=~"$instance"} - node_memory_MemAvailable_bytes{job="node",instance=~"$instance"}', "Utilisée"),
  target('node_memory_MemAvailable_bytes{job="node",instance=~"$instance"}', "Disponible", "B"),
], 12, 6, 12, 8, "bytes"));
panels.push(gauge("Espace racine", '100 * (1 - node_filesystem_avail_bytes{job="node",instance=~"$instance",mountpoint="/",fstype!~"tmpfs|overlay"} / node_filesystem_size_bytes{job="node",instance=~"$instance",mountpoint="/",fstype!~"tmpfs|overlay"})', 0, 14));
panels.push(gauge("Inodes racine", '100 * (1 - node_filesystem_files_free{job="node",instance=~"$instance",mountpoint="/",fstype!~"tmpfs|overlay"} / node_filesystem_files{job="node",instance=~"$instance",mountpoint="/",fstype!~"tmpfs|overlay"})', 6, 14));
panels.push(stat("Charge 5 min", 'node_load5{job="node",instance=~"$instance"}', 12, 14, 3));
panels.push(stat("Uptime", 'time() - node_boot_time_seconds{job="node",instance=~"$instance"}', 15, 14, 3, "s"));
panels.push(stat("Processus", 'node_procs_running{job="node",instance=~"$instance"}', 18, 14, 3));
panels.push(stat("Descripteurs utilisés", '100 * node_filefd_allocated{job="node",instance=~"$instance"} / node_filefd_maximum{job="node",instance=~"$instance"}', 21, 14, 3, "percent"));
panels.push(timeseries("Entrées et sorties disque", [
  target('sum by (device) (rate(node_disk_read_bytes_total{job="node",instance=~"$instance",device!~"loop.*|ram.*"}[$__rate_interval]))', "{{device}} lecture"),
  target('sum by (device) (rate(node_disk_written_bytes_total{job="node",instance=~"$instance",device!~"loop.*|ram.*"}[$__rate_interval]))', "{{device}} écriture", "B"),
], 0, 19, 12, 8, "Bps"));
panels.push(timeseries("Réseau", [
  target('sum by (device) (rate(node_network_receive_bytes_total{job="node",instance=~"$instance",device!~"lo|veth.*|br-.*|docker.*"}[$__rate_interval]))', "{{device}} reçu"),
  target('sum by (device) (rate(node_network_transmit_bytes_total{job="node",instance=~"$instance",device!~"lo|veth.*|br-.*|docker.*"}[$__rate_interval]))', "{{device}} envoyé", "B"),
], 12, 19, 12, 8, "Bps"));

panels.push(row("Docker et conteneurs", 27));
panels.push(timeseries("CPU par conteneur", [
  target('sum by (name) (rate(container_cpu_usage_seconds_total{job="cadvisor",image!="",name=~"$container"}[$__rate_interval])) * 100', "{{name}}"),
], 0, 28, 12, 8, "percent"));
panels.push(timeseries("Mémoire par conteneur", [
  target('container_memory_working_set_bytes{job="cadvisor",image!="",name=~"$container"}', "{{name}}"),
], 12, 28, 12, 8, "bytes"));
panels.push(timeseries("Réseau des conteneurs", [
  target('sum by (name) (rate(container_network_receive_bytes_total{job="cadvisor",image!="",name=~"$container"}[$__rate_interval]))', "{{name}} reçu"),
  target('sum by (name) (rate(container_network_transmit_bytes_total{job="cadvisor",image!="",name=~"$container"}[$__rate_interval]))', "{{name}} envoyé", "B"),
], 0, 36, 12, 8, "Bps"));
panels.push(timeseries("E/S disque des conteneurs", [
  target('sum by (name) (rate(container_fs_reads_bytes_total{job="cadvisor",image!="",name=~"$container"}[$__rate_interval]))', "{{name}} lecture"),
  target('sum by (name) (rate(container_fs_writes_bytes_total{job="cadvisor",image!="",name=~"$container"}[$__rate_interval]))', "{{name}} écriture", "B"),
], 12, 36, 12, 8, "Bps"));
panels.push(stat("Conteneurs configurés", "vps_docker_containers_total", 0, 44, 4));
panels.push(stat("Conteneurs actifs", "vps_docker_containers_running", 4, 44, 4));
panels.push(stat("Événements Docker", 'sum(rate(engine_daemon_events_total{job="docker"}[$__rate_interval]))', 8, 44, 4, "ops"));
panels.push(stat("Goroutines Docker", 'go_goroutines{job="docker"}', 12, 44, 4));
panels.push(stat("Mémoire Docker", 'process_resident_memory_bytes{job="docker"}', 16, 44, 4, "bytes"));
panels.push(stat("Redémarrages cAdvisor", 'changes(process_start_time_seconds{job="cadvisor"}[$__range])', 20, 44, 4));

panels.push(row("Maintenance locale", 48));
panels.push(stat("Redémarrage requis", "vps_reboot_required", 0, 49, 5, "bool", {
  fieldDefaults: {
    mappings: [
      {
        options: {
          "0": { color: "green", index: 0, text: "Non" },
          "1": { color: "red", index: 1, text: "Oui" },
        },
        type: "value",
      },
    ],
  },
}));
panels.push(stat("Paquets à mettre à jour", "vps_apt_upgradable", 5, 49, 5));
panels.push(stat("Unités systemd en échec", "vps_systemd_failed_units", 10, 49, 5));
panels.push(stat("Adresses bannies", "vps_fail2ban_banned_current", 15, 49, 4));
panels.push(stat("Dernière collecte locale", 'time() - max(timestamp(vps_logs_enabled))', 19, 49, 5, "s"));

const logPanels = [];
logPanels.push(textPanel(
  "Fonctionnement",
  "Loki/Alloy et cAdvisor sont optionnels. Modifier `ENABLE_LOGS` et `ENABLE_CONTAINER_METRICS` dans `/etc/default/vps-monitoring`, puis exécuter `sudo vps-monitoring apply`. Les journaux locaux restent bornés par journald et logrotate.",
  0,
  54,
  24,
  3,
));
logPanels.push(stat("Loki joignable", 'up{job="loki"}', 0, 57, 6));
logPanels.push(stat("Alloy joignable", 'up{job="alloy"}', 6, 57, 6));
logPanels.push(timeseries("Volume de journaux", [
  target('sum by (source) (count_over_time({source=~"journal|nginx"}[$__rate_interval]))', "{{source}}", "A", loki),
], 12, 57, 12, 6, "ops"));
logPanels.push(logsPanel("Journaux système, Docker et Nginx", '{source=~"journal|nginx"} |~ "(?i)$log_search"', 0, 63, 24, 11));
panels.push(row("Journaux optionnels", 53, true, logPanels));

const dashboard = {
  annotations: {
    list: [
      {
        builtIn: 1,
        datasource: { type: "grafana", uid: "-- Grafana --" },
        enable: true,
        hide: true,
        iconColor: "rgba(0, 211, 255, 1)",
        name: "Annotations et alertes",
        type: "dashboard",
      },
    ],
  },
  editable: false,
  fiscalYearStartMonth: 0,
  graphTooltip: 1,
  id: null,
  links: [],
  liveNow: false,
  panels,
  refresh: "30s",
  schemaVersion: 41,
  tags: ["vps", "debian", "docker", "observabilité"],
  templating: {
    list: [
      {
        current: {},
        datasource: prometheus,
        definition: 'label_values(node_uname_info{job="node"}, instance)',
        includeAll: true,
        label: "Hôte",
        multi: true,
        name: "instance",
        options: [],
        query: {
          query: 'label_values(node_uname_info{job="node"}, instance)',
          refId: "PrometheusVariableQueryEditor-VariableQuery",
        },
        refresh: 1,
        regex: "",
        sort: 1,
        type: "query",
      },
      {
        current: {},
        datasource: prometheus,
        definition: 'label_values(container_last_seen{job="cadvisor",image!=""}, name)',
        includeAll: true,
        label: "Conteneur",
        multi: true,
        name: "container",
        options: [],
        query: {
          query: 'label_values(container_last_seen{job="cadvisor",image!=""}, name)',
          refId: "PrometheusVariableQueryEditor-VariableQuery",
        },
        refresh: 1,
        regex: "",
        sort: 1,
        type: "query",
      },
      {
        current: { selected: true, text: ".*", value: ".*" },
        hide: 0,
        label: "Recherche dans les journaux",
        name: "log_search",
        options: [{ selected: true, text: ".*", value: ".*" }],
        query: ".*",
        type: "textbox",
      },
    ],
  },
  time: { from: "now-6h", to: "now" },
  timepicker: {},
  timezone: "browser",
  title: "VPS - Système, Docker et journaux",
  uid: "vps-observability",
  version: 1,
  weekStart: "monday",
};

fs.mkdirSync(path.dirname(output), { recursive: true });
fs.writeFileSync(output, `${JSON.stringify(dashboard, null, 2)}\n`, "utf8");
console.log(output);

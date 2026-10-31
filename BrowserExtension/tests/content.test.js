const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const api = require("../etsy-order.js");

const directory = path.resolve(__dirname, "..");
const contentScript = fs.readFileSync(path.join(directory, "content.js"), "utf8");
const recipient = {
  name: "Mia Müller", street1: "Hauptstraße 1", street2: "",
  postalCode: "66740", city: "Saarlouis", state: "", country: "Deutschland"
};

function install({ complete = true } = {}) {
  const roots = new Map();
  const timers = [];
  const toast = { hidden: true, dataset: {} };
  const caption = { textContent: "An Label Helper senden" };
  let click;
  let mutation;
  let extractions = 0;
  const button = {
    disabled: false,
    querySelector: () => caption,
    addEventListener(event, callback) { if (event === "click") click = callback; }
  };
  const shadow = {
    querySelector: (selector) => selector === ".munbyn-toast" ? toast : button
  };
  const document = {
    body: { appendChild(host) { roots.set(host.id, host); } },
    documentElement: {},
    getElementById: (id) => roots.get(id),
    createElement: () => ({ setAttribute() {}, attachShadow: () => shadow })
  };
  const location = { href: "https://www.etsy.com/your/orders/1234567890" };
  const context = vm.createContext({
    document, location,
    MunbynEtsy: {
      ...api,
      extractOrder() {
        extractions += 1;
        return {
          version: 1, orderID: "1234567890",
          recipient: complete ? recipient : { ...recipient, street1: "" },
          sourceURL: location.href
        };
      }
    },
    setTimeout(callback, delay) { timers.push({ callback, delay }); return timers.length; },
    clearTimeout() {},
    MutationObserver: class {
      constructor(callback) { mutation = callback; }
      observe() {}
    }
  });
  vm.runInContext(contentScript, context);
  return {
    roots, toast, caption, button, location, timers,
    click: () => click(), mutate: () => mutation(), extractions: () => extractions
  };
}

test("content script reads nothing before clicking and sends a complete Unicode address", () => {
  const page = install();
  assert.equal(page.roots.size, 1);
  assert.equal(page.extractions(), 0);
  page.click();
  assert.equal(page.extractions(), 1);
  assert.equal(page.button.disabled, true);
  const link = new URL(page.location.href);
  assert.equal(link.protocol, "munbyn-labeler:");
  assert.equal(link.hostname, "etsy-order");
  const payload = JSON.parse(Buffer.from(link.searchParams.get("payload"), "base64url"));
  assert.deepEqual(payload.recipient, recipient);
  assert.equal(payload.orderID, "1234567890");
  assert.equal(page.toast.dataset.kind, "success");
  page.timers.find(({ delay }) => delay === 1500).callback();
  assert.equal(page.button.disabled, false);
  assert.equal(page.caption.textContent, "An Label Helper senden");
});

test("incomplete addresses display an error instead of opening the app", () => {
  const page = install({ complete: false });
  page.click();
  assert.equal(page.location.href, "https://www.etsy.com/your/orders/1234567890");
  assert.equal(page.button.disabled, false);
  assert.equal(page.toast.hidden, false);
  assert.equal(page.toast.dataset.kind, "error");
});

test("Etsy DOM changes do not duplicate the button and restore a removed button", () => {
  const page = install();
  page.mutate();
  assert.equal(page.roots.size, 1);
  page.roots.clear();
  page.mutate();
  assert.equal(page.roots.size, 1);
});

test("manifest loads the parser before the UI on each supported order route", () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(directory, "manifest.json"), "utf8"));
  assert.equal(manifest.manifest_version, 3);
  assert.deepEqual(manifest.content_scripts[0].js, ["etsy-order.js", "content.js"]);
  assert.deepEqual(manifest.content_scripts[0].matches, [
    "https://www.etsy.com/your/orders/*",
    "https://www.etsy.com/your/shops/*/orders/*",
    "https://www.etsy.com/shop-manager/orders/*"
  ]);
  for (const file of [...manifest.content_scripts[0].js, ...Object.values(manifest.icons)]) {
    assert.equal(fs.existsSync(path.join(directory, file)), true, `Missing extension resource: ${file}`);
  }
});

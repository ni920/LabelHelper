const test = require("node:test");
const assert = require("node:assert/strict");
const {
  buildAppURL,
  extractOrder,
  findAddressInData,
  findOrderIDInData,
  isCompleteAddress,
  parseAddressLines
} = require("../etsy-order.js");

function documentFixture({ scripts = [], addressLines = [], text = "" } = {}) {
  const container = { innerText: addressLines.join("\n"), parentElement: null };
  return {
    body: { innerText: text },
    querySelectorAll(selector) {
      return selector.startsWith("script")
        ? scripts.map((textContent) => ({ textContent }))
        : addressLines.length ? [{ textContent: "Versand an", parentElement: container }] : [];
    }
  };
}

test("extracts visible shipping details even when Etsy includes malformed JSON", () => {
  const document = documentFixture({
    scripts: ["not JSON"],
    addressLines: ["Versand an", "Mia Müller", "Hauptstraße 1", "66740 Saarlouis", "Deutschland"]
  });
  const order = extractOrder(document, "https://www.etsy.com/your/orders/sold?order_id=1234567890");
  assert.equal(order.orderID, "1234567890");
  assert.equal(order.recipient.name, "Mia Müller");
  assert.equal(order.recipient.postalCode, "66740");
  assert.equal(isCompleteAddress(order.recipient), true);
});

test("extracts an order from JSON and rejects a page without a shipping address", () => {
  const document = documentFixture({
    scripts: [JSON.stringify({
      receipt: { receipt_id: 1234567890, shipping_address: {
        name: "Mia Muster", first_line: "Hauptstraße 1", zip: "66740",
        city: "Saarlouis", country_name: "Deutschland"
      } }
    })]
  });
  const order = extractOrder(document, "https://www.etsy.com/your/orders/1234567890");
  assert.equal(order.orderID, "1234567890");
  assert.equal(order.recipient.street1, "Hauptstraße 1");
  const empty = extractOrder(documentFixture(), "https://www.etsy.com/your/orders/sold");
  assert.equal(isCompleteAddress(empty.recipient), false);
});

test("parses a German shipping address block", () => {
  const address = parseAddressLines([
    "Versandadresse",
    "Mia Muster",
    "Hauptstraße 1",
    "Wohnung 2",
    "66740 Saarlouis",
    "Deutschland",
    "Adresse kopieren"
  ]);
  assert.deepEqual(address, {
    name: "Mia Muster",
    street1: "Hauptstraße 1",
    street2: "Wohnung 2",
    postalCode: "66740",
    city: "Saarlouis",
    state: "",
    country: "Deutschland"
  });
  assert.equal(isCompleteAddress(address), true);
});

test("parses the visible Etsy order-panel address headed by Versand an", () => {
  const address = parseAddressLines([
    "Versand an",
    "Mia Muster",
    "Hauptstraße 1",
    "66740 Saarlouis",
    "Deutschland",
    "+491701234567"
  ]);
  assert.deepEqual(address, {
    name: "Mia Muster",
    street1: "Hauptstraße 1",
    street2: "",
    postalCode: "66740",
    city: "Saarlouis",
    state: "",
    country: "Deutschland"
  });
  assert.equal(isCompleteAddress(address), true);
});

test("finds order and address in nested Etsy data", () => {
  const data = {
    receipt: {
      receipt_id: 1234567890,
      shipping_address: {
        name: "Mia Muster",
        first_line: "Hauptstraße 1",
        second_line: "",
        zip: "66740",
        city: "Saarlouis",
        country_name: "Deutschland"
      },
      transactions: [
        { transaction_id: 44, title: "Schmuckschatulle", quantity: 2 }
      ]
    }
  };
  assert.equal(findOrderIDInData(data), "1234567890");
  assert.equal(findAddressInData(data).street1, "Hauptstraße 1");
});

test("builds a URL-safe app link including the packing note", () => {
  const url = buildAppURL({
    version: 1,
    orderID: "123",
    recipient: {
      name: "Mia Müller",
      street1: "Hauptstraße 1",
      street2: "",
      postalCode: "66740",
      city: "Saarlouis",
      state: "",
      country: "Deutschland"
    },
    packingNote: "1 × Capy · Gold",
    sourceURL: "https://www.etsy.com/your/orders/123"
  });
  assert.match(url, /^munbyn-labeler:\/\/etsy-order\?payload=[A-Za-z0-9_-]+$/);
  const encoded = new URL(url).searchParams.get("payload");
  const decoded = JSON.parse(Buffer.from(encoded, "base64url").toString("utf8"));
  assert.equal(decoded.recipient.name, "Mia Müller");
  assert.equal(decoded.packingNote, "1 × Capy · Gold");
});

test("keeps address, quantities and variants with the explicitly selected order", () => {
  const receipt = (id, name, transactions) => ({
    receipt_id: id, shipping_address: { name, first_line: "Weg 1", zip: "12345", city: "Test" }, transactions
  });
  const document = documentFixture({ scripts: [JSON.stringify([
    receipt(2345, "Other", [{ title: "Other item", quantity: 9 }]),
    receipt(6789, "Selected", [{ title: "Capy", quantity: 1, variations: [{ formatted_value: "Gold" }] },
      { title: "Capy", quantity: 2, variations: [{ value: "Blau" }] }])
  ])] });
  const order = extractOrder(document, "https://www.etsy.com/your/orders/sold?order_id=6789");
  assert.equal(order.packingNote, "1 × Capy · Gold\n2 × Capy · Blau");
  assert.equal(order.recipient.name, "Selected");
  const overview = extractOrder(document, "https://www.etsy.com/your/orders/sold");
  assert.equal(overview.packingNote, "");
  assert.equal(isCompleteAddress(overview.recipient), false);
  const unknown = extractOrder(document, "https://www.etsy.com/your/orders/sold?order_id=9999");
  assert.equal(unknown.packingNote, "");
  assert.equal(isCompleteAddress(unknown.recipient), false);
});

test("reads visible quantity and colour inside the selected order panel", () => {
  const document = documentFixture({ addressLines: ["Versand an", "Test", "Weg 1", "12345 Test"] });
  const row = { innerText: "Capy\nMenge: 2\nFarbe: Gold", querySelectorAll: () => [{ textContent: "Capy" }] };
  const panel = { querySelectorAll: selector => selector === "[data-transaction-id]" ? [row] : document.querySelectorAll(selector) };
  document.querySelector = () => panel;
  assert.equal(extractOrder(document, "https://www.etsy.com/your/orders/12345").packingNote, "2 × Capy · Gold");
});

test("batch selection resolves only checked order rows and preserves their order", () => {
  const api = require("../etsy-order.js");
  const box = id => ({
    id: "select-order-" + id, getAttribute: () => "", closest: () => ({
      dataset: { orderId: id }, querySelectorAll: () => [], textContent: "#" + id
    })
  });
  const docs = ["1001", "1002", "1003"].map(id => ({ receipt_id: id,
    shipping_address: { name: id, first_line: "Testweg", city: "Stadt", zip: "12345" },
    transactions: [{ title: "Artikel " + id, quantity: 1 }] }));
  const document = { querySelectorAll: selector => selector.startsWith("input")
    ? [box("1003"), box("1001"), box("1003")] : [{ textContent: JSON.stringify(docs) }] };
  const orders = api.selectionOrders(document, api.selectedOrderRows(document), "https://www.etsy.com/your/orders/sold");
  assert.deepEqual(orders.map(o => [o.orderID, o.recipient.name, o.packingNote]),
    [["1003", "1003", "1 × Artikel 1003"], ["1001", "1001", "1 × Artikel 1001"]]);
  const link = new URL(api.buildBatchURL(orders));
  assert.equal(link.hostname, "etsy-orders");
  assert.deepEqual(JSON.parse(Buffer.from(link.searchParams.get("payload"), "base64url")).orders, orders);
  assert.throws(() => api.buildBatchURL([{ packingNote: "A".repeat(65536) }]), /zu groß/);
});

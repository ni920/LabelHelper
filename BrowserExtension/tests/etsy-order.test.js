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

test("builds a URL-safe app link without transferring item data", () => {
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
    items: [{ title: "Größe L", quantity: 1 }],
    sourceURL: "https://www.etsy.com/your/orders/123"
  });
  assert.match(url, /^munbyn-labeler:\/\/etsy-order\?payload=[A-Za-z0-9_-]+$/);
  const encoded = new URL(url).searchParams.get("payload");
  const decoded = JSON.parse(Buffer.from(encoded, "base64url").toString("utf8"));
  assert.equal(decoded.recipient.name, "Mia Müller");
  assert.equal("items" in decoded, false);
});

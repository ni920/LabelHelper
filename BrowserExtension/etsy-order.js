(function exposeLabelHelperEtsy(root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  root.LabelHelperEtsy = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function createLabelHelperEtsy() {
  "use strict";

  const ADDRESS_LABELS = [
    "versandadresse",
    "versand an",
    "lieferadresse",
    "empfänger",
    "empfaenger",
    "ship to",
    "shipping address",
    "delivery address",
    "deliver to"
  ];

  const IGNORED_LINES = new Set([
    ...ADDRESS_LABELS,
    "adresse kopieren",
    "copy address",
    "bearbeiten",
    "edit",
    "details"
  ]);

  function clean(value) {
    return String(value ?? "").replace(/\s+/g, " ").trim();
  }

  function normalizedKey(value) {
    return clean(value).toLowerCase().replace(/[^a-z0-9]/g, "");
  }

  function objectValue(object, aliases) {
    if (!object || typeof object !== "object" || Array.isArray(object)) return "";
    const wanted = new Set(aliases.map(normalizedKey));
    for (const [key, value] of Object.entries(object)) {
      if (!wanted.has(normalizedKey(key))) continue;
      if (["string", "number"].includes(typeof value)) return clean(value);
    }
    return "";
  }

  function walkJSON(value, visitor, path = [], depth = 0, seen = new Set()) {
    if (depth > 14 || value == null || typeof value !== "object" || seen.has(value)) return;
    seen.add(value);
    visitor(value, path);
    if (Array.isArray(value)) {
      value.slice(0, 250).forEach((entry, index) => walkJSON(entry, visitor, [...path, String(index)], depth + 1, seen));
      return;
    }
    Object.entries(value).slice(0, 250).forEach(([key, entry]) => {
      walkJSON(entry, visitor, [...path, key], depth + 1, seen);
    });
  }

  function addressFromObject(object) {
    const name = objectValue(object, ["recipient_name", "full_name", "buyer_name", "addressee", "name"]);
    const street1 = objectValue(object, ["first_line", "address_line_1", "address1", "street1", "street"]);
    const street2 = objectValue(object, ["second_line", "address_line_2", "address2", "street2"]);
    const city = objectValue(object, ["city", "locality", "town"]);
    const state = objectValue(object, ["state", "province", "region"]);
    const postalCode = objectValue(object, ["zip", "zip_code", "zipcode", "postal_code", "postalcode"]);
    const country = objectValue(object, ["country_name", "country", "country_iso", "countrycode"]);
    if (!name && !street1 && !city && !postalCode) return null;
    return { name, street1, street2, postalCode, city, state, country };
  }

  function addressScore(address, path) {
    let score = 0;
    if (address.name) score += 2;
    if (address.street1) score += 3;
    if (address.city) score += 2;
    if (address.postalCode) score += 3;
    if (address.country) score += 1;
    if (/(ship|delivery|recipient|address|buyer)/i.test(path.join("/"))) score += 6;
    return score;
  }

  function findAddressInData(data) {
    let best = null;
    let bestScore = 0;
    walkJSON(data, (value, path) => {
      if (Array.isArray(value)) return;
      const address = addressFromObject(value);
      if (!address) return;
      const score = addressScore(address, path);
      if (score > bestScore) {
        best = address;
        bestScore = score;
      }
    });
    return bestScore >= 8 ? best : null;
  }

  function findOrderIDInData(data) {
    const ids = new Set();
    walkJSON(data, value => {
      const id = objectValue(value, ["receipt_id", "order_id"]);
      if (/^\d{4,}$/.test(id)) ids.add(id);
    });
    return ids.size === 1 ? [...ids][0] : "";
  }

  function parseAddressLines(rawLines) {
    const lines = rawLines
      .map(clean)
      .filter(Boolean)
      .filter((line) => !IGNORED_LINES.has(line.toLowerCase()))
      .filter((line) => !/^(bestellung|order|receipt)\s*#/i.test(line));
    if (lines.length < 3) return null;

    let localityIndex = -1;
    let postalCode = "";
    let city = "";
    let state = "";

    for (let index = 1; index < lines.length; index += 1) {
      const line = lines[index];
      let match = line.match(/^(\d{4,6})\s+(.+)$/);
      if (match) {
        localityIndex = index;
        postalCode = match[1];
        city = clean(match[2]);
        break;
      }
      match = line.match(/^(.+?),?\s+([A-Z]{2})\s+(\d{5}(?:-\d{4})?)$/);
      if (match) {
        localityIndex = index;
        city = clean(match[1]);
        state = match[2];
        postalCode = match[3];
        break;
      }
      match = line.match(/^(.+?)\s+([A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2})$/i);
      if (match) {
        localityIndex = index;
        city = clean(match[1]);
        postalCode = match[2].toUpperCase();
        break;
      }
    }

    if (localityIndex < 2) return null;
    const name = lines[0];
    const street1 = lines[1];
    const street2 = lines.slice(2, localityIndex).join(", ");
    const country = lines[localityIndex + 1] || "";
    return { name, street1, street2, postalCode, city, state, country };
  }

  function isCompleteAddress(address) {
    return Boolean(address && address.name && address.street1 && address.postalCode && address.city);
  }

  function jsonDocuments(document) {
    const documents = [];
    const scripts = document.querySelectorAll('script[type="application/json"], script[type="application/ld+json"], script[id*="data" i]');
    for (const script of scripts) {
      const text = script.textContent?.trim();
      if (!text || text.length > 5_000_000) continue;
      try {
        documents.push(JSON.parse(text));
      } catch (_) {
        // Etsy also ships non-JSON script blocks. They are intentionally ignored.
      }
    }
    for (const script of document.scripts || []) {
      if (script.src || script.type === "application/json") continue;
      const source = script.textContent?.trim() || "";
      if (source.length > 5_000_000 || !source.includes("Etsy.Context.addData(")) continue;
      for (const line of source.split("\n")) {
        const match = line.match(/^\s*(?:window\.)?Etsy\.Context\.addData\((\{.*\})\);?\s*$/);
        if (match) {
          try { documents.push(JSON.parse(match[1])); } catch (_) { /* Non-JSON script. */ }
        }
      }
    }
    return documents;
  }

  function addressFromDocument(document) {
    const labels = new Set(ADDRESS_LABELS);
    const candidates = document.querySelectorAll("h1,h2,h3,h4,h5,[role='heading'],dt,strong");
    for (const element of candidates) {
      const label = clean(element.textContent).toLowerCase().replace(/:$/, "");
      if (!labels.has(label)) continue;
      let container = element.parentElement;
      for (let level = 0; container && level < 5; level += 1, container = container.parentElement) {
        const lines = String(container.innerText || "").split(/\n+/);
        if (lines.length > 24) continue;
        const address = parseAddressLines(lines);
        if (isCompleteAddress(address)) return address;
      }
    }
    return null;
  }

  function orderIDFromPage(url, text, dataDocuments) {
    const parsed = new URL(url);
    const queryID = parsed.searchParams.get("order_id") || parsed.searchParams.get("receipt_id");
    if (queryID) return clean(queryID);
    const pathMatch = parsed.pathname.match(/(?:orders?|receipts?)\/(\d{4,})/i);
    if (pathMatch) return pathMatch[1];
    const visibleIDs = new Set(Array.from(text.matchAll(/\b(?:Bestellung|Order|Receipt)\s*#?\s*(\d{4,})/gi), m => m[1]));
    if (visibleIDs.size === 1) return [...visibleIDs][0];
    if (visibleIDs.size > 1) return "Unbekannt";
    return findOrderIDInData(dataDocuments) || "Unbekannt";
  }

  function orderDetails(documents, orderID, scopedAddress = false) {
    let address = null;
    let packingNote = "";
    let hasOtherOrder = false;
    for (const data of documents) {
      walkJSON(data, (record) => {
        const id = objectValue(record, ["order_id", "receipt_id"]);
        if (!id) return;
        if (id !== orderID) {
          hasOtherOrder = true;
          return;
        }
        const shipping = record.shipping_address || record.shippingAddress || record.ship_to || record.recipient_address;
        if (!isCompleteAddress(address)) {
          address = shipping ? findAddressInData(shipping)
            : scopedAddress ? addressFromObject(record) : findAddressInData(record);
        }
        const rows = record.transactions || record.line_items || record.items;
        if (packingNote || !Array.isArray(rows)) return;
        const lines = rows.map((row) => {
          const title = objectValue(row, ["title", "listing_title", "product_name"]) ||
            objectValue(row?.listing, ["title"]);
          const qty = objectValue(row, ["quantity", "qty"]);
          if (!title || !/^[1-9]\d*$/.test(qty)) return "";
          const variations = Array.isArray(row.variations) ? row.variations : [];
          const values = variations.map((v) => objectValue(v, ["formatted_value", "value"])).filter(Boolean);
          return [qty + " × " + title, ...values].join(" · ");
        });
        if (lines.every(Boolean)) packingNote = lines.join("\n");
      });
    }
    return { address, packingNote, hasOtherOrder };
  }

  function visiblePackingNote(container) {
    let rows = Array.from(container.querySelectorAll("[data-transaction-id]"));
    if (!rows.length) {
      const links = Array.from(container.querySelectorAll('a[href*="/listing/"]'));
      rows = [...new Set(links.map(link => link.closest("li,article")).filter(Boolean))];
    }
    const lines = rows.map((row) => {
      const link = Array.from(row.querySelectorAll('a[href*="/listing/"]')).find(
        link => clean(link.textContent || link.getAttribute("aria-label"))
      );
      const title = clean(link?.textContent || link?.getAttribute("aria-label"));
      const quantity = row.innerText?.match(/(?:Menge|Stückzahl|Quantity|Qty)\s*:?\s*(\d+)/i)?.[1];
      if (!title || !quantity) return "";
      const variant = Array.from(row.innerText.matchAll(/(?:Farbe|Color|Größe|Size|Variante|Style|Modell)\s*:\s*([^\n]+)/gi), m => clean(m[1]));
      return [quantity + " × " + title, ...variant].join(" · ");
    });
    return lines.every(Boolean) ? lines.join("\n") : "";
  }

  function extractOrder(document, url = document.location.href) {
    const documents = jsonDocuments(document);
    const dialog = document.querySelector?.('[role="dialog"][aria-modal="true"],dialog[open]');
    const orderID = orderIDFromPage(url, String(dialog?.innerText || document.body?.innerText || ""), documents);
    const details = orderDetails(documents, orderID);
    let panel = null;
    if (/^\d+$/.test(orderID)) {
      panel = document.querySelector?.(`[data-order-id="${orderID}"],[data-receipt-id="${orderID}"]`);
      if (!panel) {
        const orderNumber = new RegExp("\\b" + orderID + "\\b");
        panel = Array.from(document.querySelectorAll('[role="dialog"],dialog[open]'))
          .find(dialog => orderNumber.test(dialog.innerText || ""));
      }
    }
    let recipient = details.address;
    if (!isCompleteAddress(recipient) && (panel || !details.hasOtherOrder)) recipient = addressFromDocument(panel || document);
    if (!isCompleteAddress(recipient) && !details.hasOtherOrder) {
      recipient = documents.map(data => findAddressInData(data)).find(isCompleteAddress);
    }
    const packingNote = details.packingNote || (panel ? visiblePackingNote(panel) : "");
    return {
      version: 1,
      orderID,
      packingNote,
      recipient: recipient || { name: "", street1: "", street2: "", postalCode: "", city: "", state: "", country: "" },
      sourceURL: url
    };
  }

  // Resolve each checked control against its own order row. Never use an
  // address from the surrounding list as a fallback for a selected order.
  function selectedOrderRows(document) {
    const result = new Map();
    const checked = document.querySelectorAll('input[type="checkbox"]:checked,[role="checkbox"][aria-checked="true"]');
    for (const box of checked) {
      const labelledBy = (box.getAttribute("aria-labelledby") || "").split(/\s+/).filter(Boolean)
        .map(id => document.getElementById(id)?.textContent);
      const label = [box.id, box.name, box.getAttribute("aria-label"), box.labels?.[0]?.textContent, ...labelledBy].map(clean).join(" ");
      if (/select all|alle auswählen|alle bestellungen auswählen/i.test(label)) continue;
      let row = box.closest("[data-order-id],[data-receipt-id]") || box.closest('tr,li,article,[role="row"]');
      if (!row) {
        for (let parent = box.parentElement; parent && parent !== document.body; parent = parent.parentElement) {
          if (parent.querySelectorAll('input[type="checkbox"],[role="checkbox"]').length !== 1) break;
          if (parent.querySelector('a[href*="order_id="],a[href*="receipt_id="],a[href*="/orders/"]')) {
            row = parent;
            break;
          }
        }
      }
      const attrID = row?.dataset?.orderId || row?.dataset?.receiptId;
      const labelledID = label.match(/(?:order|receipt|bestellung)[^0-9]{0,30}([0-9]{4,})/i)?.[1];
      const linkedIDs = new Set();
      for (const link of row?.querySelectorAll('a[href]') || []) {
        const href = link.getAttribute("href") || "";
        const id = href.match(/[?&](?:order_id|receipt_id)=(\d{4,})(?:[&#]|$)/i)?.[1]
          || href.match(/\/(?:orders?|receipts?)\/(\d{4,})(?:[/?#]|$)/i)?.[1];
        if (id) linkedIDs.add(id);
      }
      const rowNumbers = new Set(Array.from((row?.textContent || "").matchAll(/(?:#|Bestellung\s+|Order\s+)(\d{4,})\b/gi), m => m[1]));
      const rowID = rowNumbers.size === 1 ? [...rowNumbers][0] : null;
      const id = attrID || labelledID || (linkedIDs.size === 1 ? [...linkedIDs][0] : null)
        || rowID || (/order|receipt|bestellung/i.test(label) ? box.value : null);
      if (!/^\d{4,}$/.test(id || "")) {
        if (/order|receipt|bestellung/i.test(label)) throw new Error("Eine markierte Bestellung hat keine erkennbare Bestellnummer.");
        continue;
      }
      if ((labelledID && id !== labelledID) || (linkedIDs.size && (!linkedIDs.has(id) || linkedIDs.size > 1))) {
        throw new Error("Die markierte Zeile enthält mehrere Bestellnummern. Bitte die Bestelldetails öffnen.");
      }
      result.set(id, row);
    }
    return result;
  }

  function selectionOrders(document, rows, pageURL) {
    const documents = jsonDocuments(document);
    return Array.from(rows, ([orderID, row]) => {
      const details = orderDetails(documents, orderID, true);
      const address = isCompleteAddress(details.address) ? details.address : row && addressFromDocument(row);
      const url = new URL(pageURL);
      url.pathname = url.pathname.replace(/(\/(?:orders?|receipts?)\/)\d{4,}(?=\/|$)/i, (_, prefix) => prefix + orderID);
      url.searchParams.delete("receipt_id");
      url.searchParams.set("order_id", orderID);
      return { version: 1, orderID, recipient: address, packingNote: details.packingNote || (row ? visiblePackingNote(row) : ""), sourceURL: url.href };
    });
  }

  async function loadSelectedDetails(order) {
    // Read the same seller page as opening the detail link interactively.
    const response = await fetch(order.sourceURL, { credentials: "same-origin", mode: "same-origin" });
    if (!response.ok) throw new Error("Bestelldetails konnten nicht geladen werden.");
    const doc = new DOMParser().parseFromString(await response.text(), "text/html");
    const id = order.orderID;
    const panel = doc.querySelector(`[data-order-id="${id}"],[data-receipt-id="${id}"]`);
    const [resolved] = selectionOrders(doc, new Map([[id, panel]]), order.sourceURL);
    if (!isCompleteAddress(resolved.recipient)) {
      throw new Error(`Adresse zu #${id} fehlt. Öffne die Bestelldetails und wähle „Zum Sammeldruck“.`);
    }
    return { ...resolved, packingNote: resolved.packingNote || order.packingNote };
  }

  function buildBatchURL(orders) {
    const json = JSON.stringify({ version: 1, orders });
    if (new TextEncoder().encode(json).length > 65536) {
      throw new Error("Die Auswahl ist zu groß. Übernimm die Bestellungen in kleineren Gruppen.");
    }
    return `munbyn-labeler://etsy-orders?payload=${base64URL(json)}`;
  }

  function base64URL(value) {
    const bytes = new TextEncoder().encode(value);
    let binary = "";
    for (const byte of bytes) binary += String.fromCharCode(byte);
    return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
  }

  function buildAppURL(payload) {
    const appPayload = {
      version: payload.version,
      orderID: payload.orderID,
      recipient: payload.recipient,
      packingNote: payload.packingNote || undefined,
      sourceURL: payload.sourceURL
    };
    // Older Label Helper installations must still be able to open these links.
    return `munbyn-labeler://etsy-order?payload=${base64URL(JSON.stringify(appPayload))}`;
  }

  return {
    buildAppURL, buildBatchURL, selectedOrderRows, selectionOrders, loadSelectedDetails,
    extractOrder,
    findAddressInData,
    findOrderIDInData,
    isCompleteAddress,
    parseAddressLines
  };
});

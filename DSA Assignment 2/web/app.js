// Food Delivery Platform - browser client.
// Talks straight to each microservice's REST API (CORS is enabled on all of them).

const host = location.hostname || "localhost";
const api = (port) => `http://${host}:${port}/api/v1`;
const SVC = {
  customer: api(8081), restaurant: api(8082), order: api(8083), payment: api(8084),
  delivery: api(8085), notification: api(8086), admin: api(8087),
};
const STEPS = ["CREATED", "CONFIRMED", "PREPARING", "READY", "OUT_FOR_DELIVERY", "DELIVERED"];
const POLL_MS = 2000;

const state = {
  tab: "customer",
  customers: [], restaurants: [], drivers: [],
  customerId: null, restaurantId: null, driverId: null,
  shopRestaurant: null, menu: [], cart: {},
  simulating: null,
};

// ------------------------------------------------------------------ helpers
const $ = (id) => document.getElementById(id);
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const money = (n) => `NAD ${Number(n || 0).toFixed(2)}`;
const shortId = (id) => (id || "").slice(0, 12);
const time = (iso) => (iso ? new Date(iso).toLocaleTimeString() : "");
const pill = (s) => `<span class="pill ${esc(s)}">${esc(String(s).replaceAll("_", " "))}</span>`;
const restaurantName = (id) => state.restaurants.find((r) => r.restaurantId === id)?.name || id;

async function call(method, url, body) {
  const res = await fetch(url, {
    method,
    headers: body ? { "Content-Type": "application/json" } : {},
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  const data = text ? JSON.parse(text) : null;
  if (!res.ok) throw new Error(data?.message || `${res.status} ${res.statusText}`);
  return data;
}
const get = (url) => call("GET", url);

let toastTimer;
function toast(msg, isError = false) {
  const t = $("toast");
  t.textContent = msg;
  t.className = isError ? "error" : "";
  t.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => (t.hidden = true), 3500);
}

async function act(fn, okMsg) {
  try {
    await fn();
    if (okMsg) toast(okMsg);
    await refresh();
  } catch (e) {
    toast(e.message, true);
  }
}

function fillSelect(sel, items, valueKey, label, selected) {
  sel.innerHTML = items.map((i) => `<option value="${esc(i[valueKey])}">${esc(label(i))}</option>`).join("");
  if (selected) sel.value = selected;
}

function notesHtml(list) {
  if (!list.length) return `<div class="muted">Nothing yet.</div>`;
  return list.map((n) => `<div class="note"><b>${esc(n.channel)} · ${time(n.createdAt)}${n.recipientType && state.tab === "admin" ? ` · to ${esc(n.recipientType)} ${esc(n.recipientId)}` : ""}</b>${esc(n.message)}</div>`).join("");
}

function stepsHtml(status) {
  if (status === "CANCELLED") return `<div class="steps cancelled">${STEPS.map(() => "<i></i>").join("")}</div>`;
  const idx = STEPS.indexOf(status);
  return `<div class="steps">${STEPS.map((_, i) => `<i class="${i <= idx ? "done" : ""}"></i>`).join("")}</div>`;
}

// ------------------------------------------------------------------ tabs
document.querySelectorAll("#tabs button").forEach((b) =>
  b.addEventListener("click", () => {
    document.querySelectorAll("#tabs button").forEach((x) => x.classList.toggle("active", x === b));
    document.querySelectorAll(".tab").forEach((s) => s.classList.toggle("active", s.id === b.dataset.tab));
    state.tab = b.dataset.tab;
    if (state.tab === "driver") setTimeout(() => map.invalidateSize(), 50);
    refresh();
  })
);

// ------------------------------------------------------------------ health bar
async function checkHealth() {
  const parts = await Promise.all(Object.entries(SVC).map(async ([name, url]) => {
    try { await get(`${url}/health`); return `<span class="up">${name}</span>`; }
    catch { return `<span class="down">${name}</span>`; }
  }));
  $("health").innerHTML = parts.join("");
}

// ================================================================== CUSTOMER
async function refreshCustomer() {
  if (!state.customerId) return;
  const [orders, notes] = await Promise.all([
    get(`${SVC.order}/orders?customerId=${state.customerId}&limit=20`),
    get(`${SVC.notification}/notifications?recipientType=CUSTOMER&recipientId=${state.customerId}&limit=30`),
  ]);
  $("customerOrders").innerHTML = orders.length ? (await Promise.all(orders.map(customerOrderHtml))).join("")
    : `<div class="muted">No orders yet - place one above.</div>`;
  $("customerNotifications").innerHTML = notesHtml(notes);
  renderRestaurantList();
}

async function customerOrderHtml(o) {
  let delivery = "";
  if (["CONFIRMED", "PREPARING", "READY", "OUT_FOR_DELIVERY"].includes(o.status)) {
    try {
      const d = await get(`${SVC.delivery}/deliveries/order/${o.orderId}`);
      const driver = state.drivers.find((x) => x.driverId === d.driverId);
      delivery = d.driverId
        ? `<div class="small">🛵 ${esc(driver?.name || d.driverId)} · ETA ${d.etaMinutes ?? "?"} min · delivery ${pill(d.status)}</div>`
        : `<div class="small muted">Looking for a driver...</div>`;
    } catch { /* delivery not created yet */ }
  }
  const canCancel = ["CREATED", "CONFIRMED"].includes(o.status);
  const lastReason = [...o.statusHistory].reverse().find((h) => h.reason)?.reason;
  return `<div class="order">
    <header><span><b>${esc(restaurantName(o.restaurantId))}</b> <span class="muted small">${shortId(o.orderId)} · ${time(o.createdAt)}</span></span>
      <span>${money(o.totalAmount)} ${pill(o.status)}</span></header>
    ${stepsHtml(o.status)}
    <div class="small">${o.items.map((i) => `${i.quantity}× ${esc(i.name)}`).join(", ")}</div>
    ${o.status === "CANCELLED" && lastReason ? `<div class="small" style="color:var(--bad)">${esc(lastReason)}</div>` : ""}
    ${delivery}
    <details><summary>History</summary>${o.statusHistory.map((h) => `<div class="small">${time(h.at)} ${pill(h.status)} by ${esc(h.triggeredBy)}${h.reason ? ` - ${esc(h.reason)}` : ""}</div>`).join("")}</details>
    ${canCancel ? `<div class="actions"><button class="danger" onclick="cancelOrder('${o.orderId}')">Cancel order</button></div>` : ""}
  </div>`;
}

window.cancelOrder = (id) => act(() => call("POST", `${SVC.order}/orders/${id}/cancel`, { reason: "cancelled by customer" }), "Order cancelled");

function renderRestaurantList() {
  $("restaurantList").innerHTML = state.restaurants.map((r) => `
    <button class="pick ${state.shopRestaurant === r.restaurantId ? "selected" : ""}" onclick="openShop('${r.restaurantId}')">
      <span><b>${esc(r.name)}</b><br><span class="small muted">${esc(r.cuisine || "")} · ${esc(r.address.street)}</span></span>
      ${pill(r.openNow ? "open" : "closed")}
    </button>`).join("");
}

window.openShop = async (id) => {
  state.shopRestaurant = id;
  state.cart = {};
  state.menu = await get(`${SVC.restaurant}/restaurants/${id}/menu`);
  renderRestaurantList();
  renderMenu();
};

function renderMenu() {
  const rows = state.menu.map((m) => {
    const out = !m.available || m.stock === 0;
    return `<tr><td>${esc(m.name)}<br><span class="small muted">${esc(m.category || "")}${out ? " · sold out" : ` · ${m.stock} left`}</span></td>
      <td class="num">${money(m.price)}</td>
      <td class="num"><input class="qty" type="number" min="0" max="${m.stock}" value="${state.cart[m.itemId] || 0}" ${out ? "disabled" : ""}
        oninput="setQty('${m.itemId}', this.value)"></td></tr>`;
  }).join("");
  $("menu").innerHTML = `<table><tr><th>Dish</th><th class="num">Price</th><th class="num">Qty</th></tr>${rows}</table>`;
  $("orderForm").hidden = false;
  updateTotal();
}

window.setQty = (itemId, v) => { state.cart[itemId] = Math.max(0, parseInt(v) || 0); updateTotal(); };

function updateTotal() {
  const total = state.menu.reduce((s, m) => s + (state.cart[m.itemId] || 0) * m.price, 0);
  $("orderTotal").textContent = money(total);
  $("placeOrder").disabled = total === 0;
}

$("placeOrder").addEventListener("click", () => act(async () => {
  const customer = state.customers.find((c) => c.customerId === state.customerId);
  const addr = customer.addresses.find((a) => a.addressId === $("addressSelect").value) || customer.addresses[0];
  const items = state.menu.filter((m) => state.cart[m.itemId] > 0)
    .map((m) => ({ itemId: m.itemId, name: m.name, quantity: state.cart[m.itemId], unitPrice: m.price }));
  await call("POST", `${SVC.order}/orders`, {
    customerId: state.customerId,
    restaurantId: state.shopRestaurant,
    items,
    deliveryAddress: { street: addr.street, city: addr.city, postalCode: addr.postalCode, latitude: addr.latitude, longitude: addr.longitude },
  });
  state.cart = {};
  await openShop(state.shopRestaurant);
}, "Order placed! Watch it move through the lifecycle below."));

function onCustomerChange() {
  state.customerId = $("customerSelect").value;
  const c = state.customers.find((x) => x.customerId === state.customerId);
  fillSelect($("addressSelect"), c?.addresses || [], "addressId", (a) => `${a.label}: ${a.street}, ${a.city}`,
    c?.addresses.find((a) => a.isDefault)?.addressId);
  refresh();
}
$("customerSelect").addEventListener("change", onCustomerChange);

// ================================================================== RESTAURANT
async function refreshRestaurant() {
  if (!state.restaurantId) return;
  const [r, orders, menu, notes] = await Promise.all([
    get(`${SVC.restaurant}/restaurants/${state.restaurantId}`),
    get(`${SVC.order}/orders?restaurantId=${state.restaurantId}&limit=25`),
    get(`${SVC.restaurant}/restaurants/${state.restaurantId}/menu`),
    get(`${SVC.notification}/notifications?recipientType=RESTAURANT&recipientId=${state.restaurantId}&limit=30`),
  ]);
  const today = r.openingHours.map((h) => `${h.day} ${h.open}-${h.close}`).join(" · ");
  $("restaurantOpen").innerHTML = `${pill(r.openNow ? "open" : "closed")} <span class="small muted">${esc(today)}</span>`;
  $("restaurantOrders").innerHTML = orders.length ? orders.map(restaurantOrderHtml).join("") : `<div class="muted">No orders yet.</div>`;
  $("restaurantNotifications").innerHTML = notesHtml(notes);
  $("restaurantMenu").innerHTML = `<table><tr><th>Dish</th><th>Category</th><th class="num">Price</th><th class="num">Stock</th><th>Available</th></tr>
    ${menu.map((m) => `<tr><td>${esc(m.name)}</td><td>${esc(m.category || "")}</td><td class="num">${money(m.price)}</td>
      <td class="num"><button onclick="stock('${m.itemId}',-1)">−</button> <b>${m.stock}</b> <button onclick="stock('${m.itemId}',1)">+</button> <button onclick="stock('${m.itemId}',10)">+10</button></td>
      <td><button onclick="toggleItem('${m.itemId}', ${!m.available})">${m.available ? "✅ on" : "⛔ off"}</button></td></tr>`).join("")}</table>`;
}

function restaurantOrderHtml(o) {
  const btn = (status, label, cls = "") =>
    `<button class="${cls}" onclick="setStatus('${o.orderId}','${status}')">${label}</button>`;
  let actions = "";
  if (o.status === "CREATED") actions = `<span class="small muted">Waiting for payment...</span>`;
  if (o.status === "CONFIRMED") actions = btn("PREPARING", "👩‍🍳 Start preparing", "primary") + btn("CANCELLED", "Reject", "danger");
  if (o.status === "PREPARING") actions = btn("READY", "🔔 Mark ready", "primary") + btn("CANCELLED", "Cancel", "danger");
  if (o.status === "READY") actions = `<span class="small muted">Waiting for the driver to collect...</span>`;
  return `<div class="order">
    <header><span><b>${shortId(o.orderId)}</b> <span class="muted small">${time(o.createdAt)} · ${esc(o.deliveryAddress.street)}</span></span>
      <span>${money(o.totalAmount)} ${pill(o.status)}</span></header>
    ${stepsHtml(o.status)}
    <div class="small">${o.items.map((i) => `${i.quantity}× ${esc(i.name)}`).join(", ")}</div>
    <div class="actions">${actions}</div>
  </div>`;
}

window.setStatus = (id, status) => act(() => call("PATCH", `${SVC.order}/orders/${id}/status`,
  { status, reason: status === "CANCELLED" ? "cancelled by restaurant" : undefined }), `Order ${status.toLowerCase().replaceAll("_", " ")}`);
window.stock = (itemId, delta) => act(() => call("PATCH", `${SVC.restaurant}/restaurants/${state.restaurantId}/menu/${itemId}/stock`, { delta }));
window.toggleItem = (itemId, available) => act(() => call("PATCH", `${SVC.restaurant}/restaurants/${state.restaurantId}/menu/${itemId}`, { available }));

$("restaurantSelect").addEventListener("change", () => { state.restaurantId = $("restaurantSelect").value; refresh(); });
$("newItemForm").addEventListener("submit", (ev) => {
  ev.preventDefault();
  const f = new FormData(ev.target);
  act(async () => {
    await call("POST", `${SVC.restaurant}/restaurants/${state.restaurantId}/menu`, {
      name: f.get("name"), category: f.get("category") || undefined,
      price: Number(f.get("price")), stock: Number(f.get("stock")), available: true,
    });
    ev.target.reset();
  }, "Dish added");
});

// ================================================================== DRIVER
const map = L.map("map").setView([-22.565, 17.08], 13);
L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", { attribution: "© OpenStreetMap", maxZoom: 19 }).addTo(map);
const icon = (emoji) => L.divIcon({ className: "map-icon", html: emoji, iconSize: [24, 24] });
const markers = {};
let routeLine = null;

function placeMarker(key, lat, lng, emoji, label) {
  if (lat == null || lng == null) return;
  if (!markers[key]) markers[key] = L.marker([lat, lng], { icon: icon(emoji) }).addTo(map).bindTooltip(label);
  else markers[key].setLatLng([lat, lng]).setTooltipContent(label);
}

async function refreshDriver() {
  state.drivers = await get(`${SVC.delivery}/drivers`);
  const me = state.drivers.find((d) => d.driverId === state.driverId);
  if (!me) return;
  $("driverStatus").innerHTML = pill(me.status);
  $("goOnline").disabled = me.status !== "OFFLINE";
  $("goOffline").disabled = me.status !== "AVAILABLE";

  const [deliveries, notes] = await Promise.all([
    get(`${SVC.delivery}/deliveries?driverId=${state.driverId}`),
    get(`${SVC.notification}/notifications?recipientType=DRIVER&recipientId=${state.driverId}&limit=30`),
  ]);
  $("driverNotifications").innerHTML = notesHtml(notes);

  const job = deliveries.find((d) => d.status === "ASSIGNED" || d.status === "PICKED_UP");
  if (!job) {
    $("driverJob").innerHTML = `<div class="muted">No delivery assigned.${me.status === "OFFLINE" ? " Go online to receive jobs." : " Waiting for orders..."}</div>
      ${deliveries.filter((d) => d.status === "DELIVERED").length} deliveries completed.`;
  } else {
    const ready = job.orderStatus === "READY";
    $("driverJob").innerHTML = `
      <div><b>${esc(job.restaurantName || job.restaurantId)}</b> → ${esc(job.dropoffAddress || "customer")}</div>
      <div class="small">Order ${shortId(job.orderId)} · ETA ${job.etaMinutes ?? "?"} min · ${pill(job.status)} · kitchen: ${pill(job.orderStatus || "?")}</div>
      <div class="actions">
        ${job.status === "ASSIGNED" ? `<button class="primary" ${ready ? "" : "disabled title='Wait until the restaurant marks it READY'"} onclick="pickup('${job.deliveryId}')">📦 Picked up</button>` : ""}
        ${job.status === "PICKED_UP" ? `<button class="primary" onclick="complete('${job.deliveryId}')">✅ Delivered</button>` : ""}
        <button onclick="simulate()">${state.simulating ? "⏸ Stop driving" : "▶ Simulate driving"}</button>
      </div>
      ${job.status === "ASSIGNED" && !ready ? `<div class="small muted">Head to the restaurant; you can collect once the food is ready.</div>` : ""}`;
  }
  state.job = job;

  // map
  state.restaurants.forEach((r) => placeMarker(`r-${r.restaurantId}`, r.location.latitude, r.location.longitude, "🍽", r.name));
  state.drivers.forEach((d) => placeMarker(`d-${d.driverId}`, d.location.latitude, d.location.longitude,
    d.driverId === state.driverId ? "🛵" : "🚲", `${d.name} (${d.status})`));
  if (routeLine) { map.removeLayer(routeLine); routeLine = null; }
  if (markers.home) { map.removeLayer(markers.home); delete markers.home; }
  if (job) {
    const pts = [[me.location.latitude, me.location.longitude]];
    if (job.status === "ASSIGNED" && job.pickup) pts.push([job.pickup.latitude, job.pickup.longitude]);
    if (job.dropoff) { pts.push([job.dropoff.latitude, job.dropoff.longitude]); placeMarker("home", job.dropoff.latitude, job.dropoff.longitude, "🏠", job.dropoffAddress || "customer"); }
    routeLine = L.polyline(pts, { color: "#d9480f", dashArray: "6 6" }).addTo(map);
  }
}

window.pickup = (id) => act(() => call("POST", `${SVC.delivery}/deliveries/${id}/pickup`), "Picked up - order is out for delivery");
window.complete = (id) => act(async () => { stopSimulation(); await call("POST", `${SVC.delivery}/deliveries/${id}/complete`); }, "Delivered!");
const setDriverStatus = (status) => act(() => call("PATCH", `${SVC.delivery}/drivers/${state.driverId}/status`, { status }), `You are ${status.toLowerCase()}`);
$("goOnline").addEventListener("click", () => setDriverStatus("AVAILABLE"));
$("goOffline").addEventListener("click", () => setDriverStatus("OFFLINE"));
$("driverSelect").addEventListener("change", () => { stopSimulation(); state.driverId = $("driverSelect").value; refresh(); });

// Driver location simulation: every second, move ~20% of the remaining way
// toward the restaurant (before pickup) or the customer (after), publishing
// each position through PUT /drivers/{id}/location -> delivery.location-updated.
function stopSimulation() { clearInterval(state.simulating); state.simulating = null; }
window.simulate = () => {
  if (state.simulating) { stopSimulation(); refresh(); return; }
  state.simulating = setInterval(async () => {
    const me = state.drivers.find((d) => d.driverId === state.driverId);
    const job = state.job;
    const target = job && (job.status === "ASSIGNED" ? job.pickup : job.dropoff);
    if (!me || !target) { stopSimulation(); return; }
    const lat = me.location.latitude + (target.latitude - me.location.latitude) * 0.2;
    const lng = me.location.longitude + (target.longitude - me.location.longitude) * 0.2;
    try {
      await call("PUT", `${SVC.delivery}/drivers/${state.driverId}/location`, { latitude: lat, longitude: lng });
      await refreshDriver();
    } catch (e) { toast(e.message, true); stopSimulation(); }
  }, 1000);
  refresh();
};

// ================================================================== ADMIN
async function refreshAdmin() {
  const [s, rs, dp, pays, notes] = await Promise.all([
    get(`${SVC.admin}/reports/summary`),
    get(`${SVC.admin}/reports/restaurants`),
    get(`${SVC.admin}/reports/delivery-performance`),
    get(`${SVC.payment}/payments`),
    get(`${SVC.notification}/notifications?limit=40`),
  ]);
  const tile = (label, value) => `<div class="tile"><div class="label">${label}</div><div class="value">${value}</div></div>`;
  $("summaryTiles").innerHTML = tile("Orders", s.orders) + tile("Delivered", s.delivered) + tile("In progress", s.inProgress)
    + tile("Cancelled", `${s.cancelled} <span class="small muted">(${s.cancellationRate}%)</span>`) + tile("Revenue", money(s.revenue))
    + tile("Avg order → door", s.avgEndToEndMinutes != null ? `${s.avgEndToEndMinutes} min` : "–");
  $("restaurantStats").innerHTML = rs.length ? `<table><tr><th>Restaurant</th><th class="num">Orders</th><th class="num">Delivered</th><th class="num">Cancelled</th><th class="num">Revenue</th><th class="num">Avg prep</th></tr>
    ${rs.map((r) => `<tr><td>${esc(restaurantName(r.restaurantId))}</td><td class="num">${r.orders}</td><td class="num">${r.delivered}</td><td class="num">${r.cancelled} (${r.cancellationRate}%)</td><td class="num">${money(r.revenue)}</td><td class="num">${r.avgPrepMinutes != null ? r.avgPrepMinutes + " min" : "–"}</td></tr>`).join("")}</table>`
    : `<div class="muted">No orders yet.</div>`;
  const driverName = (id) => state.drivers.find((d) => d.driverId === id)?.name || id || "unassigned";
  $("deliveryStats").innerHTML = `<div class="small">${dp.deliveries} deliveries · avg pickup→door ${dp.avgDeliveryMinutes ?? "–"} min · avg order→door ${dp.avgEndToEndMinutes ?? "–"} min</div>
    <table><tr><th>Driver</th><th class="num">Jobs</th><th class="num">Avg</th><th class="num">Fastest</th></tr>
    ${dp.drivers.map((d) => `<tr><td>${esc(driverName(d.driverId))}</td><td class="num">${d.deliveries}</td><td class="num">${d.avgDeliveryMinutes ?? "–"}</td><td class="num">${d.fastestMinutes ?? "–"}</td></tr>`).join("")}</table>`;
  $("paymentsTable").innerHTML = pays.length ? `<table><tr><th>Payment</th><th>Order</th><th class="num">Amount</th><th>Status</th><th>Note</th></tr>
    ${pays.slice(0, 15).map((p) => `<tr><td>${esc(p.paymentId)}</td><td>${shortId(p.orderId)}</td><td class="num">${money(p.amount)}</td><td>${pill(p.status)}</td><td class="small">${esc(p.failureReason || "")}</td></tr>`).join("")}</table>`
    : `<div class="muted">No payments yet.</div>`;
  $("allNotifications").innerHTML = notesHtml(notes);
}

// ================================================================== in-app notifications (bell)
// The bell belongs to whoever you are on the current tab. New IN_APP
// notifications also pop up in the corner, so a status change is noticed
// even when you're looking at something else.
const seenNotifications = {};
let popupCount = 0;

function currentUser() {
  if (state.tab === "customer" && state.customerId)
    return { type: "CUSTOMER", id: state.customerId, label: state.customers.find((c) => c.customerId === state.customerId)?.name };
  if (state.tab === "restaurant" && state.restaurantId)
    return { type: "RESTAURANT", id: state.restaurantId, label: restaurantName(state.restaurantId) };
  if (state.tab === "driver" && state.driverId)
    return { type: "DRIVER", id: state.driverId, label: state.drivers.find((d) => d.driverId === state.driverId)?.name };
  return null;
}

async function refreshBell() {
  const user = currentUser();
  $("bellWrap").hidden = !user;
  if (!user) return;
  const list = await get(`${SVC.notification}/notifications?recipientType=${user.type}&recipientId=${user.id}&channel=IN_APP&limit=30`);
  const unread = list.filter((n) => !n.read).length;
  $("bellBadge").hidden = unread === 0;
  $("bellBadge").textContent = unread > 99 ? "99+" : unread;
  $("bellTitle").textContent = `Notifications - ${user.label || user.id}`;
  $("bellList").innerHTML = list.length
    ? list.map((n) => `<div class="note ${n.read ? "" : "unread"}"><b>${time(n.createdAt)} · order ${shortId(n.orderId)}</b>${esc(n.message)}</div>`).join("")
    : `<div class="muted">No notifications yet.</div>`;

  const key = user.type + ":" + user.id;
  if (!seenNotifications[key]) {
    // First look at this user's inbox: don't pop up the backlog.
    seenNotifications[key] = new Set(list.map((n) => n.notificationId));
    return;
  }
  for (const n of [...list].reverse()) {
    if (!seenNotifications[key].has(n.notificationId)) {
      seenNotifications[key].add(n.notificationId);
      popup(n.message);
    }
  }
}

function popup(message) {
  const el = document.createElement("div");
  el.className = "popup";
  el.style.top = `${70 + (popupCount % 4) * 64}px`;
  el.textContent = message;
  document.body.appendChild(el);
  popupCount++;
  setTimeout(() => { el.style.opacity = "0"; }, 4500);
  setTimeout(() => { el.remove(); popupCount--; }, 5000);
}

async function markAllRead() {
  const user = currentUser();
  if (!user) return;
  await call("POST", `${SVC.notification}/notifications/mark-read`, { recipientType: user.type, recipientId: user.id });
  await refreshBell();
}

$("bell").addEventListener("click", (ev) => {
  ev.stopPropagation();
  const panel = $("bellPanel");
  panel.hidden = !panel.hidden;
  if (!panel.hidden) setTimeout(() => markAllRead().catch(() => {}), 1500); // opened = seen
});
$("markRead").addEventListener("click", (ev) => { ev.stopPropagation(); markAllRead().catch((e) => toast(e.message, true)); });
$("bellPanel").addEventListener("click", (ev) => ev.stopPropagation());
document.addEventListener("click", () => { $("bellPanel").hidden = true; });

// ================================================================== admin: manage the platform
async function reloadDirectory() {
  [state.customers, state.restaurants, state.drivers] = await Promise.all([
    get(`${SVC.customer}/customers`), get(`${SVC.restaurant}/restaurants`), get(`${SVC.delivery}/drivers`),
  ]);
  fillSelect($("restaurantSelect"), state.restaurants, "restaurantId", (r) => r.name, state.restaurantId);
  fillSelect($("driverSelect"), state.drivers, "driverId", (d) => `${d.name} · ${d.vehicle || ""}`, state.driverId);
  fillSelect($("adminMenuRestaurant"), state.restaurants, "restaurantId", (r) => r.name, $("adminMenuRestaurant").value);
  renderRestaurantList();
}

function renderDirectory() {
  if (!$("adminMenuRestaurant").options.length)
    fillSelect($("adminMenuRestaurant"), state.restaurants, "restaurantId", (r) => r.name);
  $("adminRestaurants").innerHTML = `<table><tr><th>Name</th><th>Cuisine</th><th>Address</th><th>Now</th></tr>
    ${state.restaurants.map((r) => `<tr><td>${esc(r.name)}<br><span class="small muted">${esc(r.restaurantId)}</span></td><td>${esc(r.cuisine || "")}</td>
      <td class="small">${esc(r.address.street)}, ${esc(r.address.city)}</td><td>${pill(r.openNow ? "open" : "closed")}</td></tr>`).join("")}</table>`;
  $("adminDrivers").innerHTML = `<table><tr><th>Name</th><th>Vehicle</th><th>Phone</th><th>Status</th></tr>
    ${state.drivers.map((d) => `<tr><td>${esc(d.name)}<br><span class="small muted">${esc(d.driverId)}</span></td><td>${esc(d.vehicle || "")}</td>
      <td class="small">${esc(d.phone || "")}</td><td>${pill(d.status)}</td></tr>`).join("")}</table>`;
}

function formHandler(id, submit, okMsg) {
  $(id).addEventListener("submit", (ev) => {
    ev.preventDefault();
    const form = ev.target;
    act(async () => {
      await submit(new FormData(form));
      form.reset();
      await reloadDirectory();
    }, okMsg);
  });
}

formHandler("addRestaurantForm", async (f) => {
  const days = f.getAll("day");
  if (!days.length) throw new Error("Pick at least one opening day");
  await call("POST", `${SVC.restaurant}/restaurants`, {
    name: f.get("name"),
    cuisine: f.get("cuisine") || undefined,
    address: { street: f.get("street"), city: f.get("city") },
    location: { latitude: Number(f.get("latitude")), longitude: Number(f.get("longitude")) },
    openingHours: days.map((day) => ({ day, open: f.get("open"), close: f.get("close") })),
  });
}, "Restaurant added - customers can see it now");

formHandler("addMenuForm", async (f) => {
  await call("POST", `${SVC.restaurant}/restaurants/${f.get("restaurantId")}/menu`, {
    name: f.get("name"),
    description: f.get("description") || undefined,
    category: f.get("category") || undefined,
    price: Number(f.get("price")),
    stock: Number(f.get("stock")),
    available: true,
  });
}, "Menu item added");

formHandler("addDriverForm", async (f) => {
  const driver = await call("POST", `${SVC.delivery}/drivers`, {
    name: f.get("name"),
    phone: f.get("phone") || undefined,
    vehicle: f.get("vehicle"),
    location: { latitude: Number(f.get("latitude")), longitude: Number(f.get("longitude")) },
  });
  if (f.get("online")) await call("PATCH", `${SVC.delivery}/drivers/${driver.driverId}/status`, { status: "AVAILABLE" });
}, "Driver added");

// ================================================================== main loop
let refreshing = false;
async function refresh() {
  if (refreshing) return;
  refreshing = true;
  try {
    refreshBell().catch((e) => console.warn(e));
    if (state.tab === "customer") await refreshCustomer();
    if (state.tab === "restaurant") await refreshRestaurant();
    if (state.tab === "driver") await refreshDriver();
    if (state.tab === "admin") { await refreshAdmin(); renderDirectory(); }
  } catch (e) {
    console.warn(e);
  } finally {
    refreshing = false;
  }
}

async function init() {
  checkHealth();
  try {
    [state.customers, state.restaurants, state.drivers] = await Promise.all([
      get(`${SVC.customer}/customers`), get(`${SVC.restaurant}/restaurants`), get(`${SVC.delivery}/drivers`),
    ]);
  } catch (e) {
    toast("Can't reach the services - is `docker compose up -d` running? " + e.message, true);
    setTimeout(init, 5000);
    return;
  }
  fillSelect($("customerSelect"), state.customers, "customerId", (c) => `${c.name} (${c.customerId})`);
  fillSelect($("restaurantSelect"), state.restaurants, "restaurantId", (r) => r.name);
  fillSelect($("driverSelect"), state.drivers, "driverId", (d) => `${d.name} · ${d.vehicle || ""}`);
  state.restaurantId = $("restaurantSelect").value;
  state.driverId = $("driverSelect").value;
  onCustomerChange();
  setInterval(refresh, POLL_MS);
  setInterval(() => reloadDirectory().catch(() => {}), 15000);
  setInterval(checkHealth, 10000);
}

init();

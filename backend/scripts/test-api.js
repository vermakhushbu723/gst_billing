// End-to-end API test on an in-memory MongoDB. Run: npm run test:api
import assert from 'node:assert/strict';
import { MongoMemoryServer } from 'mongodb-memory-server';
import mongoose from 'mongoose';

const mongo = await MongoMemoryServer.create({ instance: { launchTimeout: 120000 } });
const { config } = await import('../src/config.js');
config.mongoUri = mongo.getUri('gst_test');
config.uploadDir = 'uploads-test';
const { createApp } = await import('../src/app.js');
const { seed } = await import('../src/seed.js');
const { migrate } = await import('../src/migrate.js');
await mongoose.connect(config.mongoUri);
await seed();
await migrate();
const round = (n) => Math.round(n * 100) / 100;

const server = createApp().listen(0);
const base = `http://127.0.0.1:${server.address().port}/api`;
let token = '';
async function api(method, path, body) {
  const res = await fetch(base + path, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await res.json().catch(() => null);
  return { status: res.status, data };
}

try {
  assert.equal((await api('GET', '/companies')).status, 401);
  const login = await api('POST', '/auth/login', { email: 'admin@billing.local', password: 'admin123' });
  assert.equal(login.status, 200);
  token = login.data.token;

  const companies = (await api('GET', '/companies')).data;
  assert.equal(companies.length, 5);
  const om = companies[0];
  const customer = (await api('GET', '/customers')).data[0];
  const product = (await api('GET', '/products')).data[0];

  // Reproduce the reference invoice exactly.
  const created = await api('POST', '/invoices', {
    company: om._id, customer: customer._id, invoiceNo: 290,
    invoiceDate: '2026-10-01', dueDate: '2026-10-15',
    items: [{ product: product._id, name: product.name, hsn: product.hsn, unit: 'KGS', qty: 31377, rate: 2.95, gstRate: 5 }],
  });
  assert.equal(created.status, 201, JSON.stringify(created.data));
  const inv = created.data;
  assert.equal(inv.taxableAmount, 92562.15);
  assert.equal(inv.totalTax, 4628.11);
  assert.equal(inv.cgst, 2314.05);
  assert.equal(inv.sgst, 2314.05);
  assert.equal(inv.igst, 0);
  assert.equal(inv.total, 97190.26);
  assert.equal(inv.status, 'unpaid');
  assert.equal(inv.placeOfSupply, 'Maharashtra');

  const next = await api('GET', `/invoices/next-number?company=${om._id}`);
  assert.equal(next.data.invoiceNo, 291);
  const dup = await api('POST', '/invoices', { company: om._id, customer: customer._id, invoiceNo: 290, invoiceDate: '2026-10-02', items: [{ name: 'X', qty: 1, rate: 1, gstRate: 5 }] });
  assert.equal(dup.status, 409);

  // Other state customer -> IGST
  assert.equal((await api('POST', '/customers', { name: 'No company' })).status, 400);
  const gj = await api('POST', '/customers', { company: om._id, name: 'Test Gujarat Pvt Ltd', stateCode: '24', gstin: '24ABCDE1234F1Z5', phone: '9999999999' });
  assert.equal(gj.data.pan, 'ABCDE1234F');
  const inter = await api('POST', '/invoices', { company: om._id, customer: gj.data._id, invoiceDate: '2026-10-05', items: [{ name: 'Ice', qty: 100, rate: 10, gstRate: 18 }], receivedAmount: 500 });
  assert.equal(inter.status, 201);
  assert.equal(inter.data.invoiceNo, 291);
  assert.equal(inter.data.igst, 180);
  assert.equal(inter.data.cgst, 0);
  assert.equal(inter.data.status, 'partial');
  assert.equal(inter.data.balance, 680);

  const paid = await api('POST', `/invoices/${inter.data._id}/payments`, { amount: 680, mode: 'UPI', date: '2026-10-06' });
  assert.equal(paid.data.status, 'paid');

  // Share PDF upload
  const fd = new FormData();
  fd.append('pdf', new Blob([Buffer.from('%PDF-1.4 test')], { type: 'application/pdf' }), 'a.pdf');
  const share = await (await fetch(`${base}/invoices/${inv._id}/share-pdf`, { method: 'POST', headers: { Authorization: `Bearer ${token}` }, body: fd })).json();
  assert.ok(share.url.includes('/api/public/pdf/'));
  const pub = await fetch(share.url.replace(/^https?:\/\/[^/]+\/api/, base));
  assert.equal(pub.status, 200);
  assert.match(pub.headers.get('content-disposition'), /GUJARAT_MILK_PRODUCTS_LIMITED_Sales_Invoice_290\.pdf/);

  const dash = await api('GET', `/reports/dashboard?company=${om._id}`);
  assert.equal(dash.data.outstanding, 97190.26);
  assert.equal(dash.data.months.length, 6);

  const sales = await api('GET', '/reports/sales?from=2026-10-01&to=2026-10-31');
  assert.equal(sales.data.totals.count, 2);
  assert.equal(sales.data.rateSummary.length, 2);

  const stmt = await api('GET', `/customers/${customer._id}/statement`);
  assert.equal(stmt.data.totals.balance, 97190.26);

  await api('POST', `/invoices/${inter.data._id}/cancel`);
  assert.equal((await api('GET', '/reports/sales?from=2026-10-01&to=2026-10-31')).data.totals.count, 1);

  const edit = await api('PUT', `/invoices/${inv._id}`, { company: om._id, customer: customer._id, invoiceDate: '2026-10-01', items: [{ name: 'ICE CUBES EDIBLE', qty: 1000, rate: 3, gstRate: 5 }] });
  assert.equal(edit.data.total, 3150);
  assert.equal(edit.data.invoiceNo, 290);

  // ---- Quotation -> invoice ----
  const qt = await api('POST', '/invoices', { docType: 'quotation', company: om._id, customer: customer._id, invoiceDate: '2026-10-10', items: [{ name: 'Ice', qty: 10, rate: 100, gstRate: 5 }] });
  assert.equal(qt.status, 201, JSON.stringify(qt.data));
  assert.equal(qt.data.invoiceNo, 1);
  assert.equal(qt.data.invoicePrefix, 'QT-');
  assert.equal(qt.data.status, 'open');
  assert.equal(qt.data.balance, 0);
  const qtPay = await api('POST', `/invoices/${qt.data._id}/payments`, { amount: 10 });
  assert.equal(qtPay.status, 400);
  const conv = await api('POST', `/invoices/${qt.data._id}/convert`, { invoiceDate: '2026-10-12' });
  assert.equal(conv.status, 201, JSON.stringify(conv.data));
  assert.equal(conv.data.docType, 'invoice');
  assert.equal(conv.data.invoiceNo, 292);
  assert.equal(conv.data.total, 1050);
  assert.equal((await api('GET', `/invoices/${qt.data._id}`)).data.status, 'converted');
  assert.equal((await api('POST', `/invoices/${qt.data._id}/convert`)).status, 400);
  const qList = await api('GET', '/invoices?type=quotation');
  assert.equal(qList.data.total, 1);

  // ---- Credit note reduces customer balance ----
  const cn = await api('POST', '/invoices', { docType: 'credit_note', company: om._id, customer: customer._id, invoiceDate: '2026-10-15', refInvoiceNo: '290', items: [{ name: 'ICE CUBES EDIBLE', qty: 100, rate: 3, gstRate: 5 }] });
  assert.equal(cn.status, 201);
  assert.equal(cn.data.invoicePrefix, 'CN-');
  assert.equal(cn.data.status, 'issued');
  let st2 = await api('GET', `/customers/${customer._id}/statement`);
  assert.equal(st2.data.totals.balance, round(3150 + 1050 - 315));
  assert.ok(st2.data.ledger.length >= 3);

  // ---- Payment-in allocates to oldest invoices ----
  const tooMuch = await api('POST', '/payments', { customer: customer._id, amount: 999999 });
  assert.equal(tooMuch.status, 400);
  const pin = await api('POST', '/payments', { customer: customer._id, amount: 3500, mode: 'UPI', date: '2026-10-20' });
  assert.equal(pin.status, 201, JSON.stringify(pin.data));
  assert.equal(pin.data.allocated.length, 2);
  assert.equal(pin.data.allocated[0].amount, 3150); // invoice 290 (oldest) fully paid first
  assert.equal(pin.data.allocated[1].amount, 350);
  const plist = await api('GET', '/payments?from=2026-10-01&to=2026-10-31');
  assert.ok(plist.data.total >= 3500);
  assert.ok(plist.data.byMode.UPI >= 3500);

  // ---- Expenses + settings + profit ----
  const ex = await api('POST', '/expenses', { company: om._id, date: '2026-10-05', category: 'Electricity', amount: 1200, mode: 'Bank' });
  assert.equal(ex.status, 201);
  assert.equal((await api('POST', '/expenses', { company: om._id, date: '2026-10-05', category: '', amount: 5 })).status, 400);
  const exl = await api('GET', '/expenses?from=2026-10-01&to=2026-10-31');
  assert.equal(exl.data.total, 1200);
  const settings = await api('GET', '/settings');
  assert.ok(settings.data.units.includes('KGS'));
  const upd = await api('PUT', '/settings', { units: ['KGS', 'BLOCK', 'KGS'], gstRates: [18, 5, 0] });
  assert.deepEqual(upd.data.units, ['KGS', 'BLOCK']);
  assert.deepEqual(upd.data.gstRates, [0, 5, 18]);
  const rep = await api('GET', '/reports/sales?from=2026-10-01&to=2026-10-31');
  assert.equal(rep.data.creditNotes.totals.count, 1);
  assert.equal(rep.data.expenses.total, 1200);
  assert.equal(rep.data.profit.netSales, round(rep.data.totals.taxable - 300));
  assert.equal(rep.data.profit.profit, round(rep.data.profit.netSales - 1200));
  assert.ok(rep.data.byItem.length >= 1 && rep.data.byCustomer.length >= 1);
  const dash2 = await api('GET', '/reports/dashboard');
  assert.equal(typeof dash2.data.monthExpense, 'number');

  // ---- Notifications: events + overdue alerts, per-user read state ----
  const notes = await api('GET', '/notifications');
  assert.equal(notes.status, 200);
  assert.ok(notes.data.items.some((n) => n.type === 'payment'));
  assert.ok(notes.data.items.some((n) => n.type === 'converted'));
  assert.ok(notes.data.items.some((n) => n.type === 'expense'));
  // invoice 291 (due 2026-11-04 by default, unpaid earlier) or any past-due one should raise an overdue alert
  const overdueInv = await api('POST', '/invoices', { company: om._id, customer: customer._id, invoiceDate: '2025-01-01', dueDate: '2025-01-10', items: [{ name: 'Old', qty: 1, rate: 100, gstRate: 0 }] });
  assert.equal(overdueInv.status, 201);
  (await import('../src/routes/notifications.js')).resetAlertScan();
  const withAlerts = await api('GET', '/notifications?limit=100');
  assert.ok(withAlerts.data.items.some((n) => n.type === 'overdue' && n.link === `/invoices/${overdueInv.data._id}`), 'overdue alert');
  (await import('../src/routes/notifications.js')).resetAlertScan();
  await api('GET', '/notifications');
  const { Notification } = await import('../src/models/Notification.js');
  assert.equal(await Notification.countDocuments({ type: 'overdue', link: `/invoices/${overdueInv.data._id}` }), 1, 'alert stored once');
  // own actions are already read for the actor
  assert.equal(notes.data.items.filter((n) => !n.read && n.type === 'expense').length, 0);
  const staffUser = await api('POST', '/users', { name: 'Ravi', email: 'ravi@x.com', password: 'ravi1234' });
  assert.equal(staffUser.status, 201);
  const adminToken = token;
  token = (await api('POST', '/auth/login', { email: 'ravi@x.com', password: 'ravi1234' })).data.token;
  const cnt = await api('GET', '/notifications/count');
  assert.ok(cnt.data.unread > 0);
  await api('POST', '/notifications/read-all');
  assert.equal((await api('GET', '/notifications/count')).data.unread, 0);
  token = adminToken;

  const staff = await api('POST', '/users', { name: 'Staff', email: 'staff@x.com', password: 'staff123' });
  assert.equal(staff.status, 201);
  token = (await api('POST', '/auth/login', { email: 'staff@x.com', password: 'staff123' })).data.token;
  assert.equal((await api('POST', '/companies', { name: 'X' })).status, 403);
  assert.equal((await api('PUT', '/settings', { units: ['X'] })).status, 403);
  token = adminToken;

  // ---- Export ----
  const exp = await api('GET', `/export/sales?company=${om._id}&from=2025-01-01&to=2026-12-31`);
  assert.equal(exp.status, 200, JSON.stringify(exp.data));
  assert.equal(exp.data.companyName, 'OM ICE INDUSTRIES');
  assert.equal(exp.data.columns.map((c) => c.label).join(','), 'Invoice No,Invoice Date,Contact Name,Amount,Remaining Amount,Invoice Status,Due Date,Invoice Link,Payment Type,Party Category');
  const r290 = exp.data.rows.find((r) => r[0] === '290');
  assert.ok(r290 && r290[1] === '01/10/2026' && r290[7].includes('/share/'));
  for (const t of ['quotations', 'challans', 'credit_notes', 'payments', 'expenses', 'customers', 'products', 'customer_sales', 'item_sales', 'gst']) {
    const r = await api('GET', `/export/${t}`);
    assert.equal(r.status, 200, `${t}: ${JSON.stringify(r.data)}`);
    assert.ok(Array.isArray(r.data.rows) && r.data.columns.length > 1, t);
  }
  assert.equal((await api('GET', '/export/nope')).status, 400);

  // ---- Public share page ----
  const shareTok = r290[7].split('/share/')[1];
  const pub2 = await (await fetch(`${base}/public/invoice/${shareTok}`)).json();
  assert.equal(pub2.invoice.invoiceNo, 290);
  assert.equal(pub2.company.name, 'OM ICE INDUSTRIES');
  assert.equal(pub2.invoice.shareToken, undefined);

  // ---- Company logins: each company sees only its own data ----
  const c2 = companies[1];
  const c2admin = await api('POST', '/users', { name: 'C2 Admin', email: 'c2@x.com', password: 'c2pass1', role: 'admin', loginCompany: c2._id });
  assert.equal(c2admin.status, 201, JSON.stringify(c2admin.data));
  assert.equal(c2admin.data.company, c2._id);
  assert.equal(c2admin.data.superAdmin, false);
  const c2login = await api('POST', '/auth/login', { email: 'c2@x.com', password: 'c2pass1' });
  assert.equal(c2login.data.user.companyName, companies[1].name);
  token = c2login.data.token;
  const myCompanies = (await api('GET', '/companies')).data;
  assert.equal(myCompanies.length, 1);
  assert.equal(myCompanies[0]._id, c2._id);
  assert.equal((await api('GET', `/companies/${om._id}`)).status, 404);
  assert.equal((await api('PUT', `/companies/${om._id}`, { name: 'HACK' })).status, 404);
  assert.equal((await api('POST', '/companies', { name: 'X' })).status, 403);
  assert.equal((await api('GET', '/customers')).data.length, 0);
  assert.equal((await api('GET', '/products')).data.length, 0);
  assert.equal((await api('GET', '/invoices')).data.total, 0);
  assert.equal((await api('GET', `/invoices?company=${om._id}`)).data.total, 0, 'company param is ignored for company logins');
  assert.equal((await api('GET', `/invoices/${inv._id}`)).status, 404);
  assert.equal((await api('POST', `/invoices/${inv._id}/payments`, { amount: 1 })).status, 404);
  assert.equal((await api('GET', `/customers/${customer._id}/statement`)).status, 404);
  assert.equal((await api('GET', '/payments')).data.items.length, 0);
  assert.equal((await api('GET', '/expenses')).data.items.length, 0);
  assert.equal((await api('GET', '/reports/sales')).data.totals.count, 0);
  assert.equal((await api('GET', '/export/sales')).data.rows.length, 0);
  assert.equal((await api('GET', '/export/sales')).data.companyName, companies[1].name);
  assert.equal((await api('GET', '/notifications')).data.items.filter((n) => n.company && n.company !== c2._id).length, 0);
  // their own data works and lands in their company even if another is asked for
  const myCust = await api('POST', '/customers', { company: om._id, name: 'C2 Customer', stateCode: '27' });
  assert.equal(myCust.status, 201);
  assert.equal(myCust.data.company, c2._id);
  const myProd = await api('POST', '/products', { name: 'C2 Ice', rate: 5, gstRate: 5 });
  assert.equal(myProd.data.company, c2._id);
  const myInv = await api('POST', '/invoices', { company: om._id, customer: myCust.data._id, invoiceDate: '2026-11-01', items: [{ name: 'C2 Ice', qty: 10, rate: 5, gstRate: 5 }] });
  assert.equal(myInv.status, 201, JSON.stringify(myInv.data));
  assert.equal(myInv.data.company, c2._id);
  assert.equal(myInv.data.invoiceNo, 1);
  assert.equal((await api('POST', '/invoices', { customer: customer._id, invoiceDate: '2026-11-01', items: [{ name: 'X', qty: 1, rate: 1, gstRate: 0 }] })).status, 400, 'other company customer');
  assert.equal((await api('GET', '/customers')).data.length, 1);
  const myUsers = (await api('GET', '/users')).data;
  assert.ok(myUsers.every((u) => u.company === c2._id));
  const myStaff = await api('POST', '/users', { name: 'C2 Staff', email: 'c2s@x.com', password: 'c2staff', loginCompany: null });
  assert.equal(myStaff.data.company, c2._id, 'company admin can only add logins to own company');
  const superUser = (await api('GET', '/users')).data.find((u) => u.superAdmin);
  assert.equal(superUser, undefined);
  const mySettings = await api('PUT', '/settings', { units: ['BLOCK'] });
  assert.deepEqual(mySettings.data.units, ['BLOCK']);
  token = adminToken;
  assert.notDeepEqual((await api('GET', `/settings?company=${om._id}`)).data.units, ['BLOCK'], 'masters are per company');
  // main admin still sees everything
  assert.ok((await api('GET', '/invoices?type=all&limit=200')).data.total >= 5);
  assert.equal((await api('GET', `/invoices?company=${c2._id}`)).data.total, 1);

  console.log('All API tests passed');
} finally {
  server.close();
  await mongoose.disconnect();
  await mongo.stop();
  const fs = await import('node:fs/promises');
  await fs.rm('uploads-test', { recursive: true, force: true });
}

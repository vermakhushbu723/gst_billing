// End-to-end API test on an in-memory MongoDB. Run: npm run test:api
import assert from 'node:assert/strict';
import { MongoMemoryServer } from 'mongodb-memory-server';
import mongoose from 'mongoose';

const mongo = await MongoMemoryServer.create();
const { config } = await import('../src/config.js');
config.mongoUri = mongo.getUri('gst_test');
config.uploadDir = 'uploads-test';
const { createApp } = await import('../src/app.js');
const { seed } = await import('../src/seed.js');
await mongoose.connect(config.mongoUri);
await seed();

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
  const gj = await api('POST', '/customers', { name: 'Test Gujarat Pvt Ltd', stateCode: '24', gstin: '24ABCDE1234F1Z5', phone: '9999999999' });
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

  const staff = await api('POST', '/users', { name: 'Staff', email: 'staff@x.com', password: 'staff123' });
  assert.equal(staff.status, 201);
  token = (await api('POST', '/auth/login', { email: 'staff@x.com', password: 'staff123' })).data.token;
  assert.equal((await api('POST', '/companies', { name: 'X' })).status, 403);

  console.log('All API tests passed');
} finally {
  server.close();
  await mongoose.disconnect();
  await mongo.stop();
  const fs = await import('node:fs/promises');
  await fs.rm('uploads-test', { recursive: true, force: true });
}

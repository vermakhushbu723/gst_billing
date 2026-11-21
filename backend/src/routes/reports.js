import { Router } from 'express';
import mongoose from 'mongoose';
import { Invoice } from '../models/Invoice.js';
import { round2 } from '../utils/gst.js';

const router = Router();

// "Today" in India, as YYYY-MM-DD.
const istToday = () => new Date(Date.now() + 330 * 60 * 1000).toISOString().slice(0, 10);

function baseMatch(company) {
  const m = { status: { $ne: 'cancelled' } };
  if (company && company !== 'all' && mongoose.isValidObjectId(company)) m.company = new mongoose.Types.ObjectId(String(company));
  return m;
}

router.get('/dashboard', async (req, res) => {
  const match = baseMatch(req.query.company);
  const today = istToday();
  const monthStart = `${today.slice(0, 7)}-01`;
  const d = new Date(`${monthStart}T00:00:00Z`);
  d.setUTCMonth(d.getUTCMonth() - 5);
  const sixMonthStart = d.toISOString().slice(0, 10);

  const sum = async (extra) => {
    const [r] = await Invoice.aggregate([
      { $match: { ...match, ...extra } },
      { $group: { _id: null, total: { $sum: '$total' }, tax: { $sum: '$totalTax' }, balance: { $sum: '$balance' }, count: { $sum: 1 } } },
    ]);
    return { total: round2(r?.total || 0), tax: round2(r?.tax || 0), balance: round2(r?.balance || 0), count: r?.count || 0 };
  };

  const [todayS, monthS, allS, monthly, recent, topDue] = await Promise.all([
    sum({ invoiceDate: today }),
    sum({ invoiceDate: { $gte: monthStart } }),
    sum({}),
    Invoice.aggregate([
      { $match: { ...match, invoiceDate: { $gte: sixMonthStart } } },
      { $group: { _id: { $substrBytes: ['$invoiceDate', 0, 7] }, total: { $sum: '$total' } } },
      { $sort: { _id: 1 } },
    ]),
    Invoice.find(baseMatch(req.query.company).company ? { company: req.query.company } : {})
      .select('invoiceNo invoicePrefix invoiceDate total balance status billTo.name companySnapshot.name')
      .sort({ createdAt: -1 })
      .limit(8)
      .lean(),
    Invoice.aggregate([
      { $match: { ...match, balance: { $gt: 0 } } },
      { $group: { _id: '$customer', name: { $first: '$billTo.name' }, balance: { $sum: '$balance' } } },
      { $sort: { balance: -1 } },
      { $limit: 5 },
    ]),
  ]);

  const months = [];
  for (let i = 0; i < 6; i++) {
    const m = new Date(`${sixMonthStart}T00:00:00Z`);
    m.setUTCMonth(m.getUTCMonth() + i);
    const key = m.toISOString().slice(0, 7);
    months.push({ month: key, total: round2(monthly.find((x) => x._id === key)?.total || 0) });
  }

  res.json({
    today: todayS,
    month: monthS,
    outstanding: allS.balance,
    allTime: allS,
    months,
    recent,
    topDue: topDue.map((t) => ({ customer: t._id, name: t.name, balance: round2(t.balance) })),
  });
});

// Sales register + GST summary for GSTR-1 style filing.
router.get('/sales', async (req, res) => {
  const match = baseMatch(req.query.company);
  if (req.query.from || req.query.to) {
    match.invoiceDate = {};
    if (req.query.from) match.invoiceDate.$gte = String(req.query.from);
    if (req.query.to) match.invoiceDate.$lte = String(req.query.to);
  }
  const rows = await Invoice.find(match)
    .select('invoiceNo invoicePrefix invoiceDate billTo.name billTo.gstin placeOfSupply taxableAmount cgst sgst igst totalTax total receivedAmount balance status companySnapshot.name taxSummary')
    .sort({ invoiceDate: 1, invoiceNo: 1 })
    .lean();

  const totals = { count: rows.length, taxable: 0, cgst: 0, sgst: 0, igst: 0, tax: 0, total: 0, received: 0, balance: 0 };
  const rates = new Map();
  const b2b = { count: 0, taxable: 0, tax: 0 };
  const b2c = { count: 0, taxable: 0, tax: 0 };
  for (const r of rows) {
    totals.taxable += r.taxableAmount;
    totals.cgst += r.cgst;
    totals.sgst += r.sgst;
    totals.igst += r.igst;
    totals.tax += r.totalTax;
    totals.total += r.total;
    totals.received += r.receivedAmount;
    totals.balance += r.balance;
    const bucket = r.billTo?.gstin ? b2b : b2c;
    bucket.count += 1;
    bucket.taxable += r.taxableAmount;
    bucket.tax += r.totalTax;
    for (const t of r.taxSummary || []) {
      const x = rates.get(t.rate) || { rate: t.rate, taxable: 0, cgst: 0, sgst: 0, igst: 0 };
      x.taxable += t.taxable;
      x.cgst += t.cgst;
      x.sgst += t.sgst;
      x.igst += t.igst;
      rates.set(t.rate, x);
    }
  }
  for (const k of Object.keys(totals)) if (k !== 'count') totals[k] = round2(totals[k]);
  for (const b of [b2b, b2c]) { b.taxable = round2(b.taxable); b.tax = round2(b.tax); }
  const rateSummary = [...rates.values()].sort((a, b) => a.rate - b.rate).map((x) => ({
    rate: x.rate, taxable: round2(x.taxable), cgst: round2(x.cgst), sgst: round2(x.sgst), igst: round2(x.igst),
  }));
  res.json({ rows: rows.map(({ taxSummary, ...r }) => r), totals, rateSummary, b2b, b2c });
});

export default router;

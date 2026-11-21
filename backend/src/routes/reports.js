import { Router } from 'express';
import mongoose from 'mongoose';
import { Invoice } from '../models/Invoice.js';
import { Expense } from '../models/Expense.js';
import { round2 } from '../utils/gst.js';
import { istToday } from '../utils/docs.js';

const router = Router();

function companyMatch(company) {
  return company && company !== 'all' && mongoose.isValidObjectId(company) ? { company: new mongoose.Types.ObjectId(String(company)) } : {};
}

function baseMatch(company, docType = 'invoice') {
  return { status: { $ne: 'cancelled' }, docType, ...companyMatch(company) };
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
  const sumExpenses = async (from) => {
    const [r] = await Expense.aggregate([
      { $match: { ...companyMatch(req.query.company), date: { $gte: from } } },
      { $group: { _id: null, total: { $sum: '$amount' } } },
    ]);
    return round2(r?.total || 0);
  };

  const [todayS, monthS, allS, monthly, monthlyExp, recent, topDue, credit, monthExpense, openQuotes, receivedMonth] = await Promise.all([
    sum({ invoiceDate: today }),
    sum({ invoiceDate: { $gte: monthStart } }),
    sum({}),
    Invoice.aggregate([
      { $match: { ...match, invoiceDate: { $gte: sixMonthStart } } },
      { $group: { _id: { $substrBytes: ['$invoiceDate', 0, 7] }, total: { $sum: '$total' } } },
    ]),
    Expense.aggregate([
      { $match: { ...companyMatch(req.query.company), date: { $gte: sixMonthStart } } },
      { $group: { _id: { $substrBytes: ['$date', 0, 7] }, total: { $sum: '$amount' } } },
    ]),
    Invoice.find({ ...companyMatch(req.query.company) })
      .select('docType invoiceNo invoicePrefix invoiceDate total balance status billTo.name companySnapshot.name')
      .sort({ createdAt: -1 })
      .limit(8)
      .lean(),
    Invoice.aggregate([
      { $match: { ...match, balance: { $gt: 0 } } },
      { $group: { _id: '$customer', name: { $first: '$billTo.name' }, balance: { $sum: '$balance' } } },
      { $sort: { balance: -1 } },
      { $limit: 5 },
    ]),
    Invoice.aggregate([
      { $match: baseMatch(req.query.company, 'credit_note') },
      { $group: { _id: null, total: { $sum: '$total' } } },
    ]),
    sumExpenses(monthStart),
    Invoice.countDocuments({ ...companyMatch(req.query.company), docType: 'quotation', status: 'open' }),
    Invoice.aggregate([
      { $match: match },
      { $unwind: '$payments' },
      { $match: { 'payments.date': { $gte: monthStart } } },
      { $group: { _id: null, total: { $sum: '$payments.amount' } } },
    ]),
  ]);

  const months = [];
  for (let i = 0; i < 6; i++) {
    const m = new Date(`${sixMonthStart}T00:00:00Z`);
    m.setUTCMonth(m.getUTCMonth() + i);
    const key = m.toISOString().slice(0, 7);
    months.push({
      month: key,
      total: round2(monthly.find((x) => x._id === key)?.total || 0),
      expense: round2(monthlyExp.find((x) => x._id === key)?.total || 0),
    });
  }

  res.json({
    today: todayS,
    month: monthS,
    outstanding: round2(allS.balance - (credit[0]?.total || 0)),
    allTime: allS,
    monthExpense,
    receivedMonth: round2(receivedMonth[0]?.total || 0),
    openQuotations: openQuotes,
    months,
    recent,
    topDue: topDue.map((t) => ({ customer: t._id, name: t.name, balance: round2(t.balance) })),
  });
});

function dateMatch(q, field) {
  if (!q.from && !q.to) return {};
  const m = {};
  if (q.from) m.$gte = String(q.from);
  if (q.to) m.$lte = String(q.to);
  return { [field]: m };
}

function totalsOf(rows) {
  const t = { count: rows.length, taxable: 0, cgst: 0, sgst: 0, igst: 0, tax: 0, total: 0, received: 0, balance: 0 };
  for (const r of rows) {
    t.taxable += r.taxableAmount;
    t.cgst += r.cgst;
    t.sgst += r.sgst;
    t.igst += r.igst;
    t.tax += r.totalTax;
    t.total += r.total;
    t.received += r.receivedAmount || 0;
    t.balance += r.balance || 0;
  }
  for (const k of Object.keys(t)) if (k !== 'count') t[k] = round2(t[k]);
  return t;
}

// Sales register, GST summary, customer/item-wise sales, credit notes, expenses and profit.
router.get('/sales', async (req, res) => {
  const fields = 'docType invoiceNo invoicePrefix invoiceDate customer billTo.name billTo.gstin placeOfSupply refInvoiceNo taxableAmount cgst sgst igst totalTax total receivedAmount balance status companySnapshot.name taxSummary items';
  const [rows, creditRows, expenses] = await Promise.all([
    Invoice.find({ ...baseMatch(req.query.company), ...dateMatch(req.query, 'invoiceDate') }).select(fields).sort({ invoiceDate: 1, invoiceNo: 1 }).lean(),
    Invoice.find({ ...baseMatch(req.query.company, 'credit_note'), ...dateMatch(req.query, 'invoiceDate') }).select(fields).sort({ invoiceDate: 1, invoiceNo: 1 }).lean(),
    Expense.find({ ...companyMatch(req.query.company), ...dateMatch(req.query, 'date') }).lean(),
  ]);

  const totals = totalsOf(rows);
  const creditTotals = totalsOf(creditRows);

  const rates = new Map();
  const addRates = (list, sign) => {
    for (const r of list) {
      for (const t of r.taxSummary || []) {
        const x = rates.get(t.rate) || { rate: t.rate, taxable: 0, cgst: 0, sgst: 0, igst: 0 };
        x.taxable += sign * t.taxable;
        x.cgst += sign * t.cgst;
        x.sgst += sign * t.sgst;
        x.igst += sign * t.igst;
        rates.set(t.rate, x);
      }
    }
  };
  addRates(rows, 1);
  addRates(creditRows, -1);
  const rateSummary = [...rates.values()].sort((a, b) => a.rate - b.rate).map((x) => ({
    rate: x.rate, taxable: round2(x.taxable), cgst: round2(x.cgst), sgst: round2(x.sgst), igst: round2(x.igst),
  }));

  const b2b = { count: 0, taxable: 0, tax: 0 };
  const b2c = { count: 0, taxable: 0, tax: 0 };
  const customers = new Map();
  const items = new Map();
  for (const r of rows) {
    const bucket = r.billTo?.gstin ? b2b : b2c;
    bucket.count += 1;
    bucket.taxable += r.taxableAmount;
    bucket.tax += r.totalTax;
    const ck = String(r.customer);
    const c = customers.get(ck) || { customer: r.customer, name: r.billTo?.name || '', gstin: r.billTo?.gstin || '', count: 0, taxable: 0, tax: 0, total: 0, balance: 0 };
    c.count += 1;
    c.taxable += r.taxableAmount;
    c.tax += r.totalTax;
    c.total += r.total;
    c.balance += r.balance;
    customers.set(ck, c);
    for (const it of r.items || []) {
      const ik = `${(it.name || '').toUpperCase()}|${it.unit || ''}`;
      const x = items.get(ik) || { name: it.name, unit: it.unit, hsn: it.hsn, qty: 0, taxable: 0, tax: 0, amount: 0 };
      x.qty += it.qty;
      x.taxable += it.taxable;
      x.tax += it.tax;
      x.amount += it.amount;
      items.set(ik, x);
    }
  }
  for (const b of [b2b, b2c]) { b.taxable = round2(b.taxable); b.tax = round2(b.tax); }
  const r2 = (o, keys) => { for (const k of keys) o[k] = round2(o[k]); return o; };
  const byCustomer = [...customers.values()].map((c) => r2(c, ['taxable', 'tax', 'total', 'balance'])).sort((a, b) => b.total - a.total);
  const byItem = [...items.values()].map((i) => r2(i, ['qty', 'taxable', 'tax', 'amount'])).sort((a, b) => b.amount - a.amount);

  const expenseByCategory = {};
  for (const e of expenses) expenseByCategory[e.category] = round2((expenseByCategory[e.category] || 0) + e.amount);
  const expenseTotal = round2(expenses.reduce((s, e) => s + e.amount, 0));
  const netSales = round2(totals.taxable - creditTotals.taxable);

  const strip = ({ taxSummary, items: _i, ...r }) => r;
  res.json({
    rows: rows.map(strip),
    totals,
    rateSummary,
    b2b,
    b2c,
    byCustomer,
    byItem,
    creditNotes: { rows: creditRows.map(strip), totals: creditTotals },
    expenses: { total: expenseTotal, byCategory: expenseByCategory },
    profit: {
      sales: totals.taxable,
      returns: creditTotals.taxable,
      netSales,
      expenses: expenseTotal,
      profit: round2(netSales - expenseTotal),
      gstPayable: round2(totals.tax - creditTotals.tax),
    },
  });
});

export default router;

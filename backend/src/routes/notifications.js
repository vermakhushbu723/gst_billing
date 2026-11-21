import { Router } from 'express';
import mongoose from 'mongoose';
import { Notification } from '../models/Notification.js';
import { Invoice } from '../models/Invoice.js';
import { addDays, istToday } from '../utils/docs.js';
import { docNo, money, notify } from '../utils/notify.js';

const router = Router();

let lastScan = 0;
export const resetAlertScan = () => {
  lastScan = 0;
};

// Turns overdue / due-soon invoices and expired quotations into notifications.
// Runs at most once every 10 minutes, triggered by whoever opens the bell.
async function scanAlerts() {
  if (Date.now() - lastScan < 10 * 60 * 1000) return;
  lastScan = Date.now();
  const today = istToday();
  const soon = addDays(today, 2);
  const [overdue, dueSoon, expired] = await Promise.all([
    Invoice.find({ docType: 'invoice', status: { $in: ['unpaid', 'partial'] }, dueDate: { $ne: '', $lt: today } })
      .select('invoiceNo invoicePrefix dueDate balance billTo.name company').sort({ dueDate: -1 }).limit(100).lean(),
    Invoice.find({ docType: 'invoice', status: { $in: ['unpaid', 'partial'] }, dueDate: { $gte: today, $lte: soon } })
      .select('invoiceNo invoicePrefix dueDate balance billTo.name company').limit(100).lean(),
    Invoice.find({ docType: 'quotation', status: 'open', dueDate: { $ne: '', $lt: today } })
      .select('invoiceNo invoicePrefix dueDate total billTo.name company').limit(100).lean(),
  ]);
  const fmt = (d) => d.split('-').reverse().join('/');
  for (const i of overdue) {
    await notify({
      key: `overdue:${i._id}:${i.dueDate}`, type: 'overdue', severity: 'warning', company: i.company, link: `/invoices/${i._id}`,
      title: `Payment overdue — Invoice #${docNo(i)}`,
      body: `${i.billTo?.name || ''}: ${money(i.balance)} was due on ${fmt(i.dueDate)}`,
    });
  }
  for (const i of dueSoon) {
    await notify({
      key: `due_soon:${i._id}:${i.dueDate}`, type: 'due_soon', severity: 'info', company: i.company, link: `/invoices/${i._id}`,
      title: `Payment due ${i.dueDate === today ? 'today' : 'soon'} — Invoice #${docNo(i)}`,
      body: `${i.billTo?.name || ''}: ${money(i.balance)} due on ${fmt(i.dueDate)}`,
    });
  }
  for (const q of expired) {
    await notify({
      key: `quotation_expired:${q._id}:${q.dueDate}`, type: 'quotation_expired', severity: 'warning', company: q.company, link: `/invoices/${q._id}`,
      title: `Quotation #${docNo(q)} has expired`,
      body: `${q.billTo?.name || ''}: ${money(q.total)}, valid till ${fmt(q.dueDate)}. Convert or follow up.`,
    });
  }
}

router.get('/', async (req, res) => {
  await scanAlerts().catch((e) => console.error('alert scan failed', e.message));
  const me = req.user._id;
  const limit = Math.min(100, Math.max(1, Number(req.query.limit) || 40));
  const filter = req.query.unread === '1' ? { readBy: { $ne: me } } : {};
  const [items, unread] = await Promise.all([
    Notification.find(filter).sort({ createdAt: -1 }).limit(limit).lean(),
    Notification.countDocuments({ readBy: { $ne: me } }),
  ]);
  res.json({
    unread,
    items: items.map(({ readBy, ...n }) => ({ ...n, read: (readBy || []).some((u) => String(u) === String(me)) })),
  });
});

router.get('/count', async (req, res) => {
  await scanAlerts().catch(() => {});
  res.json({ unread: await Notification.countDocuments({ readBy: { $ne: req.user._id } }) });
});

router.post('/read-all', async (req, res) => {
  await Notification.updateMany({ readBy: { $ne: req.user._id } }, { $addToSet: { readBy: req.user._id } });
  res.json({ ok: true });
});

router.post('/:id/read', async (req, res) => {
  if (mongoose.isValidObjectId(req.params.id)) {
    await Notification.updateOne({ _id: req.params.id }, { $addToSet: { readBy: req.user._id } });
  }
  res.json({ ok: true });
});

export default router;

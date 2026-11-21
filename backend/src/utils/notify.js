import { Notification } from '../models/Notification.js';

const money = (n) => `₹${Number(n || 0).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
export { money };

/**
 * Records an in-app notification. Never throws: a failed notification must not
 * break the action that triggered it. With `key`, the same alert is stored once.
 */
export async function notify({ key, type = 'info', severity = 'info', title, body = '', link = '', company, actor }) {
  try {
    const doc = { type, severity, title, body, link, company, actor, readBy: actor ? [actor] : [] };
    if (key) {
      await Notification.updateOne({ key }, { $setOnInsert: { key, ...doc } }, { upsert: true });
    } else {
      await Notification.create(doc);
    }
  } catch (e) {
    if (e?.code !== 11000) console.error('notify failed', e.message);
  }
}

const LABEL = { invoice: 'Invoice', quotation: 'Quotation', credit_note: 'Credit note', challan: 'Delivery challan' };
export const docLabel = (t) => LABEL[t] || 'Invoice';
export const docNo = (inv) => `${inv.invoicePrefix || ''}${inv.invoiceNo}`;

import mongoose from 'mongoose';

// In-app notification, visible to every user. `readBy` tracks who has seen it.
const notificationSchema = new mongoose.Schema(
  {
    key: { type: String, unique: true, sparse: true }, // de-duplicates generated alerts
    type: { type: String, default: 'info' }, // invoice, payment, expense, overdue, due_soon, quotation_expired...
    severity: { type: String, enum: ['info', 'success', 'warning'], default: 'info' },
    title: { type: String, required: true },
    body: { type: String, default: '' },
    link: { type: String, default: '' }, // app route, e.g. /invoices/<id>
    company: { type: mongoose.Schema.Types.ObjectId, ref: 'Company' },
    actor: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    readBy: [{ type: mongoose.Schema.Types.ObjectId, ref: 'User' }],
  },
  { timestamps: true },
);

notificationSchema.index({ createdAt: -1 });

export const Notification = mongoose.model('Notification', notificationSchema);

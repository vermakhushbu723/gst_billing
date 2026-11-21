import mongoose from 'mongoose';

const expenseSchema = new mongoose.Schema(
  {
    company: { type: mongoose.Schema.Types.ObjectId, ref: 'Company', required: true },
    date: { type: String, required: true }, // YYYY-MM-DD
    category: { type: String, required: true, trim: true },
    amount: { type: Number, required: true, min: 0 },
    mode: { type: String, default: 'Cash' },
    paidTo: { type: String, default: '', trim: true },
    note: { type: String, default: '', trim: true },
    createdBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
  },
  { timestamps: true },
);

expenseSchema.index({ date: -1 });

export const Expense = mongoose.model('Expense', expenseSchema);

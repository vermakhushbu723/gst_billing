import mongoose from 'mongoose';

// One document holding the editable master lists used across the app.
export const DEFAULT_SETTINGS = {
  units: ['KGS', 'NOS', 'PCS', 'BAGS', 'BOX', 'LTR', 'TON', 'MTR', 'DOZ', 'SET'],
  gstRates: [0, 0.25, 3, 5, 12, 18, 28, 40],
  paymentModes: ['Cash', 'UPI', 'Bank', 'Cheque', 'Card'],
  expenseCategories: ['Electricity', 'Salary', 'Rent', 'Diesel / Fuel', 'Transport', 'Repair & Maintenance', 'Packing Material', 'Water', 'Office', 'Other'],
};

const settingSchema = new mongoose.Schema(
  {
    key: { type: String, default: 'main', unique: true },
    units: { type: [String], default: DEFAULT_SETTINGS.units },
    gstRates: { type: [Number], default: DEFAULT_SETTINGS.gstRates },
    paymentModes: { type: [String], default: DEFAULT_SETTINGS.paymentModes },
    expenseCategories: { type: [String], default: DEFAULT_SETTINGS.expenseCategories },
  },
  { timestamps: true },
);

export const Setting = mongoose.model('Setting', settingSchema);

export async function getSettings() {
  return Setting.findOneAndUpdate({ key: 'main' }, { $setOnInsert: { key: 'main' } }, { upsert: true, new: true, setDefaultsOnInsert: true }).lean();
}

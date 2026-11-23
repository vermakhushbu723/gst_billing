import mongoose from 'mongoose';

const customerSchema = new mongoose.Schema(
  {
    company: { type: mongoose.Schema.Types.ObjectId, ref: 'Company', index: true },
    name: { type: String, required: true, trim: true },
    category: { type: String, default: '', trim: true }, // party category (Masters)
    phone: { type: String, default: '', trim: true },
    email: { type: String, default: '', trim: true },
    gstin: { type: String, default: '', uppercase: true, trim: true },
    pan: { type: String, default: '', uppercase: true, trim: true },
    billingAddress: { type: String, default: '', trim: true },
    shippingName: { type: String, default: '', trim: true },
    shippingAddress: { type: String, default: '', trim: true },
    sameAsBilling: { type: Boolean, default: true },
    stateCode: { type: String, default: '27' },
    state: { type: String, default: 'Maharashtra' },
    openingBalance: { type: Number, default: 0 },
    active: { type: Boolean, default: true },
  },
  { timestamps: true },
);

customerSchema.index({ name: 1 });

export const Customer = mongoose.model('Customer', customerSchema);

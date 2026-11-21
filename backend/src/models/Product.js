import mongoose from 'mongoose';

const productSchema = new mongoose.Schema(
  {
    name: { type: String, required: true, trim: true },
    description: { type: String, default: '', trim: true },
    hsn: { type: String, default: '', trim: true },
    unit: { type: String, default: 'KGS', trim: true },
    rate: { type: Number, default: 0 },
    gstRate: { type: Number, default: 5 },
    active: { type: Boolean, default: true },
  },
  { timestamps: true },
);

export const Product = mongoose.model('Product', productSchema);

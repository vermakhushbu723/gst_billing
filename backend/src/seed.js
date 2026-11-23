// Creates the first admin, the 5 companies, and sample customer/product.
// Safe to run more than once: it only adds what is missing.
import 'dotenv/config';
import mongoose from 'mongoose';
import bcrypt from 'bcryptjs';
import { config } from './config.js';
import { User } from './models/User.js';
import { Company } from './models/Company.js';
import { Customer } from './models/Customer.js';
import { Product } from './models/Product.js';

const DEFAULT_TERMS = [
  'Goods once sold will not be taken back or exchanged',
  'All disputes are subject to Mumbai jurisdiction only',
];

export async function seed() {
  const email = (process.env.SEED_ADMIN_EMAIL || 'admin@billing.local').toLowerCase();
  if (!(await User.exists({ email }))) {
    await User.create({
      name: process.env.SEED_ADMIN_NAME || 'Admin',
      email,
      role: 'admin',
      passwordHash: await bcrypt.hash(process.env.SEED_ADMIN_PASSWORD || 'admin123', 10),
    });
    console.log(`Admin created: ${email}`);
  }

  if ((await Company.countDocuments()) === 0) {
    await Company.create({
      name: 'OM ICE INDUSTRIES',
      tagline: 'PURE RO TREATED ICE CUBES',
      address: 'A/8, GIRIRAJ INDUSTRIAL ESTATE, MAHAKALI CAVES ROAD, ANDHERI - EAST, Mumbai Suburban, Maharashtra',
      city: 'Mumbai',
      stateCode: '27',
      state: 'Maharashtra',
      pincode: '400092',
      mobile: '7831888888',
      email: 'omiceindustries2001@gmail.com',
      gstin: '27AAEFO6474A1ZC',
      bank: {
        accountName: 'Om ice industries',
        ifsc: 'IBKL0452JSB',
        accountNo: '004012056003502',
        bankName: 'Jain Sahakari Bank, Jain Sahakari Bank',
        branch: 'IMPS',
      },
      terms: DEFAULT_TERMS,
      nextInvoiceNo: 1,
    });
    // Four more companies to be filled in from the Companies screen.
    for (let i = 2; i <= 5; i++) {
      await Company.create({
        name: `COMPANY ${i} (EDIT DETAILS)`,
        tagline: '',
        city: 'Mumbai',
        stateCode: '27',
        state: 'Maharashtra',
        terms: DEFAULT_TERMS,
      });
    }
    console.log('5 companies created');
  }

  const firstCompany = await Company.findOne().sort({ createdAt: 1 }).select('_id').lean();
  if ((await Customer.countDocuments()) === 0) {
    await Customer.create({
      company: firstCompany?._id,
      name: 'GUJARAT MILK PRODUCTS LIMITED',
      billingAddress: '17AB, GOVERNMENT INDUSTRIAL ESTATES, HINDUSTAN NAKA, CHARKOP, KANDIVALI WEST, Mumbai City, Maharashtra, Mumbai, Maharashtra, 400067',
      gstin: '27AABCG0233H1Z2',
      pan: 'AABCG0233H',
      stateCode: '27',
      state: 'Maharashtra',
      sameAsBilling: true,
    });
  }
  if ((await Product.countDocuments()) === 0) {
    await Product.create({ company: firstCompany?._id, name: 'ICE CUBES EDIBLE', hsn: '22019010', unit: 'KGS', rate: 2.95, gstRate: 5 });
  }
}

if (process.argv[1] && process.argv[1].endsWith('seed.js')) {
  await mongoose.connect(config.mongoUri);
  await seed();
  await mongoose.disconnect();
  console.log('Seed done');
}

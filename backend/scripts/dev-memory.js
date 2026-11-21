// Runs the API on an in-memory MongoDB with seed data. For local testing only:
// all data is lost when the process stops.
import { MongoMemoryServer } from 'mongodb-memory-server';
import mongoose from 'mongoose';

const mongo = await MongoMemoryServer.create({ instance: { launchTimeout: 120000 } });
process.env.MONGODB_URI = mongo.getUri('gst_billing');
const { config } = await import('../src/config.js');
config.mongoUri = process.env.MONGODB_URI;
const { createApp } = await import('../src/app.js');
const { seed } = await import('../src/seed.js');

const { migrate } = await import('../src/migrate.js');
await mongoose.connect(config.mongoUri);
await seed();
await migrate();
createApp().listen(config.port, '0.0.0.0', () => console.log(`GST Billing API (in-memory DB) on :${config.port}`));

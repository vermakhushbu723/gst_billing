import mongoose from 'mongoose';
import { config } from './config.js';
import { createApp } from './app.js';
import { migrate } from './migrate.js';

await mongoose.connect(config.mongoUri);
console.log('MongoDB connected');
await migrate();
createApp().listen(config.port, '0.0.0.0', () => console.log(`GST Billing API on :${config.port}`));

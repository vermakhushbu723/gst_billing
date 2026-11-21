import mongoose from 'mongoose';
import { config } from './config.js';
import { createApp } from './app.js';

await mongoose.connect(config.mongoUri);
console.log('MongoDB connected');
createApp().listen(config.port, '0.0.0.0', () => console.log(`GST Billing API on :${config.port}`));

import fs from 'node:fs';
import path from 'node:path';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import compression from 'compression';
import { config } from './config.js';
import { errorHandler, requireAuth } from './middleware/auth.js';
import authRoutes from './routes/auth.js';
import userRoutes from './routes/users.js';
import companyRoutes from './routes/companies.js';
import customerRoutes from './routes/customers.js';
import productRoutes from './routes/products.js';
import invoiceRoutes from './routes/invoices.js';
import reportRoutes from './routes/reports.js';
import publicRoutes from './routes/public.js';
import paymentRoutes from './routes/payments.js';
import expenseRoutes from './routes/expenses.js';
import settingRoutes from './routes/settings.js';
import notificationRoutes from './routes/notifications.js';

export function createApp() {
  const app = express();
  app.set('trust proxy', 1);
  // CSP off: the Flutter web build loads CanvasKit/WASM, and the API only returns JSON/PDF.
  app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' }, contentSecurityPolicy: false, crossOriginEmbedderPolicy: false }));
  app.use(cors({ origin: config.corsOrigins.includes('*') ? true : config.corsOrigins }));
  app.use(compression());
  app.use(express.json({ limit: '5mb' }));

  app.get('/api/health', (_req, res) => res.json({ ok: true }));
  app.use('/api/public', publicRoutes);
  app.use('/api/auth', authRoutes);
  app.use('/api/users', requireAuth, userRoutes);
  app.use('/api/companies', requireAuth, companyRoutes);
  app.use('/api/customers', requireAuth, customerRoutes);
  app.use('/api/products', requireAuth, productRoutes);
  app.use('/api/invoices', requireAuth, invoiceRoutes);
  app.use('/api/reports', requireAuth, reportRoutes);
  app.use('/api/payments', requireAuth, paymentRoutes);
  app.use('/api/expenses', requireAuth, expenseRoutes);
  app.use('/api/settings', requireAuth, settingRoutes);
  app.use('/api/notifications', requireAuth, notificationRoutes);

  app.use('/api', (_req, res) => res.status(404).json({ message: 'Not found' }));
  app.use(errorHandler);

  // Optional: serve the Flutter web build from the same server (one link for app + API).
  if (config.webDir && fs.existsSync(path.join(config.webDir, 'index.html'))) {
    const dir = path.resolve(config.webDir);
    app.use(express.static(dir, { index: false, maxAge: '1h' }));
    app.get(/^(?!\/api).*/, (_req, res) => {
      res.setHeader('Cache-Control', 'no-cache');
      res.sendFile(path.join(dir, 'index.html'));
    });
  }
  return app;
}

# GST Billing

Tax invoice software for 5 companies. One Flutter codebase builds the Android app and the web link; both use the same Node.js API and MongoDB.

The invoice PDF follows the OM ICE INDUSTRIES Sales Invoice 290 layout: header with logo, invoice/due date bar, Bill To / Ship To, items with tax, subtotal, bank details, terms, CGST/SGST (or IGST), amount in words, signature and receiver's box.

```
gst_billing/
  backend/   Node 20 + Express 5 + MongoDB (mongoose)
  app/       Flutter app — Android APK + web
```

## Screens

| Screen | What it does |
|---|---|
| Login | Email/mobile + password (admin or staff) |
| Dashboard | Today / month sales, outstanding, GST, received, expenses, profit, open quotations, sales vs expenses chart, quick actions |
| Invoices | List with search, company, status and date filters, totals |
| Quotations | Estimates in the same format; **convert to invoice** in one tap |
| Delivery Challans | Goods sent before billing; convert to invoice |
| Credit Notes | Sales returns against an invoice; reduce customer balance and GST |
| New / Edit document | Company, auto number per type and company, dates, customer, place of supply, items, live CGST/SGST/IGST, amount received |
| Document view | PDF preview, **Print**, **WhatsApp**, Download/Share, Original/Duplicate/Triplicate, payments, convert, cancel/restore, duplicate, delete |
| Payments In | All money received; **Receive Payment** settles the oldest unpaid invoices first |
| Expenses | Kharcha by company and category, with totals |
| Customers | Pending balance, add/edit (GSTIN → state + PAN), ledger with running balance, statement PDF, WhatsApp reminder |
| Products | Rate, unit, GST %, HSN |
| Companies | 5 firms: logo, signature, address, GSTIN, bank, terms, prefixes and numbering, colour |
| Units, GST & Lists | Admin edits units, GST rates, payment modes and expense categories (nothing hard-coded) |
| Reports | Sales register, GST summary (net of credit notes), B2B/B2C, P&L, customer-wise, item-wise, credit notes, expenses; print + CSV |
| Settings / Users | Profile, change password, admin manages staff logins |

## Company logins

- **Main admin** (a login with no company) sees and manages every company.
- **Company login** (Companies → Logins, or Users & Logins with a company chosen) sees only that company: its invoices, quotations, challans, credit notes, customers, products, payments, expenses, reports, notifications, masters and logins.
  - **Company Admin** can also edit the company details and add staff logins for the company.
  - **Staff** can do the day-to-day billing.
- The server enforces this. For a company login, the company is set on every request, and opening another company's record returns 404.

## Export / Download

Open it from Dashboard → **Export / Download** (also in the sidebar and the profile menu).

- Choose the report, the company and the dates (or all dates).
- Download as **Excel (.xlsx)**, **CSV** or **PDF**.
- The **Sales Summary** CSV has exactly the same layout as `rai_ice_depot_invoice_report.csv`:
  - a header block, then the columns `Invoice No, Invoice Date, Contact Name, Amount, Remaining Amount, Invoice Status, Due Date, Invoice Link, Payment Type, Party Category`;
  - Invoice Link is a public page (`/share/<token>`) where the customer can view, print and download the invoice without logging in.
- **All data** exports every report (one sheet each in Excel).

## WhatsApp

On the invoice screen, **WhatsApp** offers two ways:

1. **Send PDF file**: the phone's share sheet opens with the PDF attached. Pick WhatsApp and then the chat. This works in the Android app and in mobile browsers. On a computer the PDF downloads instead.
2. **Send PDF link to a number**: the PDF is uploaded and WhatsApp opens on the customer's number with the message and a download link (`/api/public/pdf/<random token>.pdf`). This works everywhere.

Sending with no tap at all (fully automatic) would need the WhatsApp Business Cloud API, which requires a Meta business account.

## Run locally

```bash
# API with a throw-away in-memory database and sample data (no MongoDB needed)
cd backend
npm install
npm run dev:memory            # http://localhost:4100/api  login: admin@billing.local / admin123

# App in Chrome (debug builds talk to localhost:4100)
cd app
flutter run -d chrome
```

With a real MongoDB, copy `backend/.env.example` to `.env`, set `MONGODB_URI` and `JWT_SECRET`, then run `npm run seed` once and `npm start`.

Tests:

```bash
cd backend && npm run test:api     # full API flow; reproduces invoice 290 totals exactly
cd app && flutter test             # GST maths, amount in words, PDF generation
```

## Build

```bash
# Web: served by the backend at the same address (set WEB_DIR=../app/build/web in .env)
cd app
flutter build web --release --base-href=/

# Android APK, pointing at the live API
flutter build apk --release --dart-define=API_URL=https://YOUR-DOMAIN/api
# -> app/build/app/outputs/flutter-apk/app-release.apk
```

If the web app is hosted on a different domain from the API, build it with `--dart-define=API_URL=https://YOUR-DOMAIN/api` and add that domain to `CORS_ORIGINS`.

## Deploy (VPS with nginx + pm2)

1. Copy `backend/` to the server, `npm ci --omit=dev`, and create `.env`. Set `NODE_ENV=production`, a long random `JWT_SECRET`, `MONGODB_URI`, `PUBLIC_URL=https://YOUR-DOMAIN`, `WEB_DIR=/path/to/web` and a free `PORT`.
2. `npm run seed` once. **Change the admin password after the first login.**
3. `pm2 start src/server.js --name gst-billing`.
4. In nginx, proxy the domain to that port with `client_max_body_size 15m` (PDF uploads), then add a certbot certificate.

Uploaded WhatsApp PDFs are stored in `backend/uploads/pdf/`. Keep this folder when updating.

## Still to fill in

- Details of companies 2 to 5 (seeded as "COMPANY n (EDIT DETAILS)"): name, address, GSTIN, bank and logo, from the Companies screen.
- Logo and signature images for OM ICE INDUSTRIES (upload them on its company screen).

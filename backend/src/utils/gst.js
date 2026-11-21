// GST calculation. Kept identical to app/lib/core/gst.dart so the live preview
// in the app always matches what the server stores.
//
// Per line: taxable = qty * rate, tax = taxable * gst%, amount = taxable + tax.
// Summary: per GST rate, CGST and SGST (same state) or IGST (other state).
// This mirrors the reference invoice (Taxable 92,562.15, CGST/SGST 2,314.05,
// Total 97,190.26).

export const round2 = (n) => Math.round((Number(n) + Number.EPSILON) * 100) / 100;

export function computeInvoice(rawItems, { intraState }) {
  const items = (rawItems || []).map((it) => {
    const qty = Number(it.qty) || 0;
    const rate = Number(it.rate) || 0;
    const gstRate = Number(it.gstRate) || 0;
    const taxable = round2(qty * rate);
    const tax = round2((taxable * gstRate) / 100);
    return {
      product: it.product || undefined,
      name: String(it.name || '').trim(),
      description: String(it.description || '').trim(),
      hsn: String(it.hsn || '').trim(),
      unit: String(it.unit || '').trim(),
      qty,
      rate,
      gstRate,
      taxable,
      tax,
      amount: round2(taxable + tax),
    };
  });

  const byRate = new Map();
  for (const it of items) {
    byRate.set(it.gstRate, round2((byRate.get(it.gstRate) || 0) + it.taxable));
  }
  const taxSummary = [...byRate.entries()]
    .sort((a, b) => a[0] - b[0])
    .filter(([rate]) => rate > 0)
    .map(([rate, taxable]) => {
      if (intraState) {
        const half = round2((taxable * rate) / 200);
        return { rate, taxable, cgst: half, sgst: half, igst: 0 };
      }
      return { rate, taxable, cgst: 0, sgst: 0, igst: round2((taxable * rate) / 100) };
    });

  const taxableAmount = round2(items.reduce((s, i) => s + i.taxable, 0));
  const totalTax = round2(items.reduce((s, i) => s + i.tax, 0));
  const totalQty = round2(items.reduce((s, i) => s + i.qty, 0));
  return {
    items,
    taxSummary,
    totalQty,
    taxableAmount,
    totalTax,
    cgst: round2(taxSummary.reduce((s, t) => s + t.cgst, 0)),
    sgst: round2(taxSummary.reduce((s, t) => s + t.sgst, 0)),
    igst: round2(taxSummary.reduce((s, t) => s + t.igst, 0)),
    total: round2(taxableAmount + totalTax),
  };
}

export function paymentStatus(total, received) {
  if (received <= 0) return 'unpaid';
  if (received + 0.005 >= total) return 'paid';
  return 'partial';
}

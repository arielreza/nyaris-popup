/**
 * Format a number as Indonesian Rupiah
 * e.g. 150000 -> "Rp 150.000"
 */
export function formatRupiah(amount) {
  if (amount === null || amount === undefined || isNaN(amount)) return 'Rp 0'
  return 'Rp ' + Number(amount).toLocaleString('id-ID')
}

/**
 * Generate a random POS receipt code
 * e.g. "POS-8492"
 */
export function generateReceiptCode() {
  const num = Math.floor(1000 + Math.random() * 9000)
  return `POS-${num}`
}

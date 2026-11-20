import jsPDF from 'jspdf'
import autoTable from 'jspdf-autotable'
import { formatRupiah } from '@/lib/currency.js'

/**
 * Sanitize strings for safe file naming
 */
function slugify(text) {
  return String(text || '')
    .trim()
    .replace(/[^\w\s-]/g, '')
    .replace(/[\s_-]+/g, '_')
    .replace(/^-+|-+$/g, '') || 'document'
}

/**
 * Format timestamp into Indonesian locale string
 */
function formatDateTime(dateInput) {
  if (!dateInput) return '—'
  const d = new Date(dateInput)
  if (isNaN(d.getTime())) return String(dateInput)
  return d.toLocaleString('id-ID', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
}

/**
 * Format short time for transaction rows (e.g. "14:25" or "18 Nov 14:25")
 */
function formatShortTime(dateInput) {
  if (!dateInput) return '—'
  const d = new Date(dateInput)
  if (isNaN(d.getTime())) return String(dateInput)
  return d.toLocaleString('id-ID', {
    day: 'numeric',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  })
}

/**
 * Apply universal page footers to all pages of the document
 */
function applyPageFooters(doc) {
  const pageCount = doc.getNumberOfPages()
  for (let i = 1; i <= pageCount; i++) {
    doc.setPage(i)
    doc.setFont('helvetica', 'normal')
    doc.setFontSize(8)
    doc.setTextColor(148, 163, 184) // slate-400

    // Footer divider line
    doc.setDrawColor(226, 232, 240) // slate-200
    doc.setLineWidth(0.3)
    doc.line(14, 284, 196, 284)

    // Left brand note & right page counter
    doc.text('PopUpPOS • Central POS & Revenue-Share System', 14, 289)
    doc.text(`Halaman ${i} dari ${pageCount}`, 196, 289, { align: 'right' })
  }
}

/**
 * Generate Event Settlement PDF ("Export All PDF")
 *
 * @param {Object} options
 * @param {Object} options.event Event object (name, venue, event_dates, venue_share_percent, organizer_share_percent)
 * @param {Object} options.summary Summary figures (totalGross, totalVenueCut, totalOrganizerCut, totalTenantNet, totalQris, totalCash)
 * @param {Object} [options.paymentBreakdown] Payment reconciliation object (qrisTotal, qrisCount, cashTotal, cashCount)
 * @param {Array} options.tenantRows Settlement rows with tenant details & calculated cuts
 */
export function generateEventSettlementPdf({ event, summary, tenantRows = [], paymentBreakdown = null }) {
  const doc = new jsPDF({
    orientation: 'portrait',
    unit: 'mm',
    format: 'a4',
  })

  const eventName = event?.name || 'Event Pop-up'
  const venueName = event?.venue || '—'
  const eventDates = event?.event_dates || '—'
  const printedAt = formatDateTime(new Date())

  // ── Top Brand Accent Strip ──
  doc.setFillColor(15, 23, 42) // slate-900
  doc.rect(0, 0, 210, 5, 'F')
  doc.setFillColor(16, 185, 129) // emerald-500
  doc.rect(0, 5, 210, 1.5, 'F')

  // ── Header Section ──
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(9)
  doc.setTextColor(16, 185, 129) // emerald-500
  doc.text('POPUPPOS • SETTLEMENT & REVENUE-SHARE REPORT', 14, 14)

  doc.setFont('helvetica', 'bold')
  doc.setFontSize(16)
  doc.setTextColor(15, 23, 42) // slate-900
  doc.text('LAPORAN SETTLEMENT & BAGI HASIL EVENT', 14, 21)

  // Event Metadata Box (gray background)
  doc.setFillColor(248, 250, 252) // slate-50
  doc.setDrawColor(226, 232, 240) // slate-200
  doc.roundedRect(14, 25, 182, 19, 2, 2, 'FD')

  const defaultVenue = Number(event?.venue_share_percent ?? 10)
  const defaultOrg = Number(event?.organizer_share_percent ?? 0)

  doc.setFont('helvetica', 'bold')
  doc.setFontSize(9)
  doc.setTextColor(15, 23, 42)
  doc.text(`Event: ${eventName}`, 18, 30.5)

  doc.setFont('helvetica', 'normal')
  doc.setFontSize(8)
  doc.setTextColor(71, 85, 105) // slate-600
  doc.text(`Lokasi / Venue: ${venueName}`, 18, 36)
  doc.text(`Skema Bagi Hasil: Venue ${defaultVenue}% • EO ${defaultOrg}% (Total Potongan: ${defaultVenue + defaultOrg}%)`, 18, 41)

  doc.text(`Tanggal Event: ${eventDates}`, 115, 30.5)
  doc.text(`Dicetak pada: ${printedAt}`, 115, 36)

  // ── Financial Summary Grid (4 Cards + Payment Methods) ──
  const startSummaryY = 48
  const colWidth = 43.5
  const gap = 2.6
  const cardHeight = 17

  // Card 1: Total Gross
  doc.setFillColor(241, 245, 249) // slate-100
  doc.setDrawColor(203, 213, 225)
  doc.roundedRect(14, startSummaryY, colWidth, cardHeight, 1.5, 1.5, 'FD')
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(7)
  doc.setTextColor(100, 116, 139)
  doc.text('TOTAL GROSS SALES', 17, startSummaryY + 5)
  doc.setFontSize(10.5)
  doc.setTextColor(15, 23, 42)
  doc.text(formatRupiah(summary?.totalGross || 0), 17, startSummaryY + 12)

  // Card 2: Venue Cut
  const card2X = 14 + colWidth + gap
  doc.setFillColor(245, 243, 255) // violet-50
  doc.setDrawColor(221, 214, 254)
  doc.roundedRect(card2X, startSummaryY, colWidth, cardHeight, 1.5, 1.5, 'FD')
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(7)
  doc.setTextColor(109, 40, 217) // violet-700
  doc.text('VENUE CUT', card2X + 3, startSummaryY + 5)
  doc.setFontSize(10.5)
  doc.setTextColor(109, 40, 217)
  doc.text(formatRupiah(summary?.totalVenueCut || 0), card2X + 3, startSummaryY + 12)

  // Card 3: Organizer Cut
  const card3X = card2X + colWidth + gap
  doc.setFillColor(255, 251, 235) // amber-50
  doc.setDrawColor(253, 230, 138)
  doc.roundedRect(card3X, startSummaryY, colWidth, cardHeight, 1.5, 1.5, 'FD')
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(7)
  doc.setTextColor(180, 83, 9) // amber-700
  doc.text('ORGANIZER / EO CUT', card3X + 3, startSummaryY + 5)
  doc.setFontSize(10.5)
  doc.setTextColor(180, 83, 9)
  doc.text(formatRupiah(summary?.totalOrganizerCut || 0), card3X + 3, startSummaryY + 12)

  // Card 4: Tenant Net Payout
  const card4X = card3X + colWidth + gap
  doc.setFillColor(236, 253, 245) // emerald-50
  doc.setDrawColor(167, 243, 208)
  doc.roundedRect(card4X, startSummaryY, colWidth, cardHeight, 1.5, 1.5, 'FD')
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(7)
  doc.setTextColor(4, 120, 87) // emerald-700
  doc.text('HAK BERSIH TENANT', card4X + 3, startSummaryY + 5)
  doc.setFontSize(10.5)
  doc.setTextColor(4, 120, 87)
  doc.text(formatRupiah(summary?.totalTenantNet || 0), card4X + 3, startSummaryY + 12)

  // ── Payment Reconciliation Strip (End-of-Day) ──
  const pBreakdown = paymentBreakdown || summary?.paymentBreakdown || null
  const qrisTotal = pBreakdown?.qrisTotal ?? summary?.totalQris ?? 0
  const qrisCount = pBreakdown?.qrisCount ?? 0
  const cashTotal = pBreakdown?.cashTotal ?? summary?.totalCash ?? 0
  const cashCount = pBreakdown?.cashCount ?? 0

  const qrisStr = qrisCount > 0
    ? `QRIS: ${formatRupiah(qrisTotal)} (${qrisCount} trx)`
    : `QRIS: ${formatRupiah(qrisTotal)}`
  const cashStr = cashCount > 0
    ? `CASH: ${formatRupiah(cashTotal)} (${cashCount} trx)`
    : `CASH: ${formatRupiah(cashTotal)}`
  const trxSuffix = (qrisCount + cashCount) > 0 ? `   •   Total: ${qrisCount + cashCount} Transaksi` : ''

  const paymentY = startSummaryY + cardHeight + 3.5
  doc.setFillColor(248, 250, 252)
  doc.setDrawColor(226, 232, 240)
  doc.roundedRect(14, paymentY, 182, 8, 1, 1, 'FD')

  doc.setFont('helvetica', 'bold')
  doc.setFontSize(7.5)
  doc.setTextColor(15, 23, 42)
  doc.text('Rekonsiliasi Pembayaran:', 18, paymentY + 5.2)

  doc.setFont('helvetica', 'normal')
  doc.setTextColor(71, 85, 105)
  doc.text(
    `${qrisStr}   •   ${cashStr}${trxSuffix}   •   Total Tenant: ${tenantRows.length} Brand`,
    58,
    paymentY + 5.2
  )

  // ── Main Settlement Table (autoTable) ──
  const tableData = tenantRows.map((r) => {
    const vPercent = Number(r.venue_share_percent ?? defaultVenue)
    const oPercent = Number(r.organizer_share_percent ?? defaultOrg)

    const venueText = vPercent !== defaultVenue
      ? `${formatRupiah(r.venueCut || 0)} (${vPercent}%)`
      : formatRupiah(r.venueCut || 0)

    const orgText = oPercent !== defaultOrg
      ? `${formatRupiah(r.orgCut || 0)} (${oPercent}%)`
      : formatRupiah(r.orgCut || 0)

    return [
      r.booth_number || '—',
      r.name || 'Unnamed',
      r.category || '—',
      r.bank_info || '—',
      formatRupiah(r.gross || 0),
      venueText,
      orgText,
      formatRupiah(r.net || 0),
      r.payout_status || 'PENDING',
    ]
  })

  autoTable(doc, {
    startY: paymentY + 11,
    margin: { left: 14, right: 14, bottom: 18 },
    head: [[
      'Booth',
      'Tenant / Brand',
      'Kategori',
      'Rekening / Bank',
      'Gross Sales',
      `Venue Cut (${defaultVenue}%)`,
      `EO Cut (${defaultOrg}%)`,
      'Net Payout',
      'Status',
    ]],
    body: tableData.length > 0 ? tableData : [['—', 'Belum ada data tenant', '—', '—', 'Rp 0', 'Rp 0', 'Rp 0', 'Rp 0', '—']],
    foot: [
      [
        { content: 'TOTAL KESELURUHAN', colSpan: 4, styles: { halign: 'right', fontStyle: 'bold', textColor: [15, 23, 42] } },
        { content: formatRupiah(summary?.totalGross || 0), styles: { halign: 'right', fontStyle: 'bold' } },
        { content: formatRupiah(summary?.totalVenueCut || 0), styles: { halign: 'right', fontStyle: 'bold', textColor: [109, 40, 217] } },
        { content: formatRupiah(summary?.totalOrganizerCut || 0), styles: { halign: 'right', fontStyle: 'bold', textColor: [180, 83, 9] } },
        { content: formatRupiah(summary?.totalTenantNet || 0), styles: { halign: 'right', fontStyle: 'bold', textColor: [4, 120, 87] } },
        { content: '', styles: { halign: 'center' } },
      ],
    ],
    theme: 'grid',
    styles: {
      font: 'helvetica',
      fontSize: 7.2,
      cellPadding: 2,
      textColor: [30, 41, 59],
      lineColor: [226, 232, 240],
      lineWidth: 0.15,
    },
    headStyles: {
      fillColor: [15, 23, 42], // slate-900
      textColor: [255, 255, 255],
      fontStyle: 'bold',
      halign: 'left',
    },
    footStyles: {
      fillColor: [241, 245, 249],
      textColor: [15, 23, 42],
      fontStyle: 'bold',
    },
    columnStyles: {
      0: { cellWidth: 12, halign: 'center', fontStyle: 'bold' }, // Booth
      1: { cellWidth: 30, fontStyle: 'bold' },                   // Tenant
      2: { cellWidth: 18 },                                     // Kategori
      3: { cellWidth: 20, fontSize: 6.8 },                      // Rekening
      4: { cellWidth: 21, halign: 'right' },                    // Gross
      5: { cellWidth: 22, halign: 'right' },                    // Venue Cut (with %)
      6: { cellWidth: 21, halign: 'right' },                    // EO Cut (with %)
      7: { cellWidth: 21, halign: 'right', fontStyle: 'bold', textColor: [4, 120, 87] }, // Net
      8: { cellWidth: 17, halign: 'center', fontSize: 6.8, fontStyle: 'bold' }, // Status (clean fit for PENDING/SETTLED)
    },
    alternateRowStyles: {
      fillColor: [248, 250, 252],
    },
    didParseCell: (data) => {
      // Highlight SETTLED / PENDING badges in status column
      if (data.section === 'body' && data.column.index === 8) {
        if (data.cell.raw === 'SETTLED') {
          data.cell.styles.textColor = [4, 120, 87]
        } else if (data.cell.raw === 'PENDING') {
          data.cell.styles.textColor = [180, 83, 9]
        }
      }
    },
  })

  // Apply page numbers & footer to all pages
  applyPageFooters(doc)

  // Save PDF
  const eventSlug = slugify(eventName)
  const dateStr = new Date().toISOString().slice(0, 10)
  doc.save(`Settlement_${eventSlug}_${dateStr}.pdf`)
}

/**
 * Generate Tenant Settlement Slip PDF (per-row "PDF")
 *
 * @param {Object} options
 * @param {Object} options.event Event object (name, venue, event_dates, etc.)
 * @param {Object} options.tenantRow Tenant object with summary fields (name, booth_number, category, bank_info, payout_status, gross, venueCut, orgCut, net, venue_share_percent, organizer_share_percent)
 * @param {Array} options.tenantItems List of non-voided transaction items belonging to this tenant
 */
export function generateTenantSettlementPdf({ event, tenantRow, tenantItems = [] }) {
  const doc = new jsPDF({
    orientation: 'portrait',
    unit: 'mm',
    format: 'a4',
  })

  const eventName = event?.name || 'Event Pop-up'
  const venueName = event?.venue || '—'
  const eventDates = event?.event_dates || '—'
  const printedAt = formatDateTime(new Date())

  const tenantName = tenantRow?.name || 'Tenant'
  const boothNumber = tenantRow?.booth_number || '—'
  const category = tenantRow?.category || '—'
  const bankInfo = tenantRow?.bank_info || '—'
  const payoutStatus = tenantRow?.payout_status || 'PENDING'

  const gross = Number(tenantRow?.gross || 0)
  const venueCut = Number(tenantRow?.venueCut || 0)
  const orgCut = Number(tenantRow?.orgCut || 0)
  const totalCut = venueCut + orgCut
  const net = Number(tenantRow?.net || 0)

  const venuePercent = Number(tenantRow?.venue_share_percent ?? event?.venue_share_percent ?? 10)
  const orgPercent = Number(tenantRow?.organizer_share_percent ?? event?.organizer_share_percent ?? 0)
  const totalPercent = venuePercent + orgPercent

  // ── Top Brand Accent Strip ──
  doc.setFillColor(15, 23, 42) // slate-900
  doc.rect(0, 0, 210, 5, 'F')
  doc.setFillColor(16, 185, 129) // emerald-500
  doc.rect(0, 5, 210, 1.5, 'F')

  // ── Header Section ──
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(9)
  doc.setTextColor(16, 185, 129) // emerald-500
  doc.text('POPUPPOS • TENANT SETTLEMENT SLIP', 14, 14)

  doc.setFont('helvetica', 'bold')
  doc.setFontSize(16)
  doc.setTextColor(15, 23, 42)
  doc.text('SLIP SETTLEMENT TENANT', 14, 21)

  // Event Context Bar
  doc.setFont('helvetica', 'normal')
  doc.setFontSize(8.5)
  doc.setTextColor(71, 85, 105)
  doc.text(`Event: ${eventName}   •   Lokasi: ${venueName}   •   Tanggal: ${eventDates}`, 14, 27)

  // ── Tenant Details Card (Left) & Financial Summary Card (Right) ──
  const cardY = 32
  const leftCardWidth = 88
  const rightCardWidth = 91
  const cardH = 43

  // Left Card: Tenant Profile
  doc.setFillColor(248, 250, 252) // slate-50
  doc.setDrawColor(226, 232, 240)
  doc.roundedRect(14, cardY, leftCardWidth, cardH, 2, 2, 'FD')

  doc.setFont('helvetica', 'bold')
  doc.setFontSize(8)
  doc.setTextColor(100, 116, 139)
  doc.text('INFORMASI TENANT & REKENING', 18, cardY + 6)

  doc.setFont('helvetica', 'bold')
  doc.setFontSize(12.5)
  doc.setTextColor(15, 23, 42)
  doc.text(tenantName, 18, cardY + 13)

  doc.setFont('helvetica', 'normal')
  doc.setFontSize(8.5)
  doc.setTextColor(71, 85, 105)
  doc.text('Booth:', 18, cardY + 19)
  doc.setFont('helvetica', 'bold')
  doc.setTextColor(15, 23, 42)
  doc.text(boothNumber, 48, cardY + 19)

  doc.setFont('helvetica', 'normal')
  doc.setTextColor(71, 85, 105)
  doc.text('Kategori:', 18, cardY + 25)
  doc.setTextColor(15, 23, 42)
  doc.text(category, 48, cardY + 25)

  doc.setTextColor(71, 85, 105)
  doc.text('Rekening / Bank:', 18, cardY + 31)
  doc.setFont('helvetica', 'bold')
  doc.setTextColor(15, 23, 42)
  doc.text(bankInfo, 48, cardY + 31)

  doc.setFont('helvetica', 'normal')
  doc.setTextColor(71, 85, 105)
  doc.text('Status Payout:', 18, cardY + 37)
  if (payoutStatus === 'SETTLED') {
    doc.setFont('helvetica', 'bold')
    doc.setTextColor(4, 120, 87) // emerald-700
    doc.text('SETTLED (Lunas / Ditransfer)', 48, cardY + 37)
  } else {
    doc.setFont('helvetica', 'bold')
    doc.setTextColor(180, 83, 9) // amber-700
    doc.text('PENDING (Menunggu Transfer)', 48, cardY + 37)
  }

  // Right Card: Financial Breakdown & Net Payout (Combined Total Cut only)
  const rightCardX = 14 + leftCardWidth + 3
  doc.setFillColor(248, 250, 252)
  doc.setDrawColor(226, 232, 240)
  doc.roundedRect(rightCardX, cardY, rightCardWidth, cardH, 2, 2, 'FD')

  doc.setFont('helvetica', 'bold')
  doc.setFontSize(8)
  doc.setTextColor(100, 116, 139)
  doc.text('RINGKASAN BAGI HASIL', rightCardX + 4, cardY + 6)

  // Breakdown lines: Total Gross and combined Potongan Bagi Hasil
  doc.setFont('helvetica', 'normal')
  doc.setFontSize(8.5)
  doc.setTextColor(51, 65, 85)

  doc.text('Total Gross Sales:', rightCardX + 4, cardY + 14)
  doc.setFont('helvetica', 'bold')
  doc.text(formatRupiah(gross), rightCardX + rightCardWidth - 4, cardY + 14, { align: 'right' })

  doc.setFont('helvetica', 'normal')
  doc.setTextColor(180, 83, 9) // amber-700
  doc.text(`Potongan Bagi Hasil (${totalPercent}%):`, rightCardX + 4, cardY + 21)
  doc.setFont('helvetica', 'bold')
  doc.text(`- ${formatRupiah(totalCut)}`, rightCardX + rightCardWidth - 4, cardY + 21, { align: 'right' })

  // Net Take-Home Highlight Strip
  const netBoxY = cardY + 27
  const netPercent = Math.max(0, 100 - totalPercent)
  doc.setFillColor(236, 253, 245) // emerald-50
  doc.setDrawColor(167, 243, 208) // emerald-200
  doc.roundedRect(rightCardX + 3, netBoxY, rightCardWidth - 6, 13, 1.5, 1.5, 'FD')

  doc.setFont('helvetica', 'bold')
  doc.setFontSize(8)
  doc.setTextColor(4, 120, 87)
  doc.text('HAK BERSIH (NET PAYOUT):', rightCardX + 6, netBoxY + 5.5)
  doc.setFontSize(11)
  doc.text(formatRupiah(net), rightCardX + rightCardWidth - 6, netBoxY + 8.5, { align: 'right' })
  doc.setFontSize(6.5)
  doc.setTextColor(6, 95, 70)
  doc.text(`(${netPercent}% dari gross sales)`, rightCardX + 6, netBoxY + 10.5)

  // ── Section Title: Transaction Audit Log ──
  const auditHeaderY = cardY + cardH + 7
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(10)
  doc.setTextColor(15, 23, 42)
  doc.text('Rincian Transaksi Penjualan (Audit Trail)', 14, auditHeaderY)

  doc.setFont('helvetica', 'normal')
  doc.setFontSize(8)
  doc.setTextColor(100, 116, 139)
  doc.text(`Total ${tenantItems.length} item transaksi berhasil dicatat di event ini`, 196, auditHeaderY, { align: 'right' })

  // ── Transaction Items Table (autoTable) ──
  // Sort items newest first or chronological
  const sortedItems = [...tenantItems].sort((a, b) => {
    const da = new Date(a.transactions?.created_at || 0).getTime()
    const db = new Date(b.transactions?.created_at || 0).getTime()
    return da - db
  })

  const itemRows = sortedItems.map((item) => {
    const itemGross = Number(item.gross_amount || 0)
    const itemVenueCut = Number(item.venue_cut || 0)
    const itemOrgCut = Number(item.organizer_cut || 0)
    const itemTotalCut = itemVenueCut + itemOrgCut
    const itemNet = Number(item.tenant_net || 0)

    return [
      formatShortTime(item.transactions?.created_at),
      item.transactions?.receipt_code || '—',
      item.transactions?.payment_method || '—',
      item.item_note || '—',
      formatRupiah(itemGross),
      formatRupiah(itemTotalCut),
      formatRupiah(itemNet),
    ]
  })

  autoTable(doc, {
    startY: auditHeaderY + 3,
    margin: { left: 14, right: 14, bottom: 18 },
    head: [[
      'Waktu',
      'No. Struk',
      'Metode',
      'Catatan / Item',
      'Gross Sales',
      'Potongan',
      'Net Hak Tenant',
    ]],
    body: itemRows.length > 0 ? itemRows : [['—', '—', '—', 'Belum ada transaksi tercatat untuk tenant ini', 'Rp 0', 'Rp 0', 'Rp 0']],
    foot: [
      [
        { content: 'TOTAL TRANSAKSI', colSpan: 4, styles: { halign: 'right', fontStyle: 'bold', textColor: [15, 23, 42] } },
        { content: formatRupiah(gross), styles: { halign: 'right', fontStyle: 'bold' } },
        { content: formatRupiah(totalCut), styles: { halign: 'right', fontStyle: 'bold', textColor: [180, 83, 9] } },
        { content: formatRupiah(net), styles: { halign: 'right', fontStyle: 'bold', textColor: [4, 120, 87] } },
      ],
    ],
    theme: 'grid',
    styles: {
      font: 'helvetica',
      fontSize: 7.5,
      cellPadding: 2,
      textColor: [30, 41, 59],
      lineColor: [226, 232, 240],
      lineWidth: 0.15,
    },
    headStyles: {
      fillColor: [15, 23, 42],
      textColor: [255, 255, 255],
      fontStyle: 'bold',
      halign: 'left',
    },
    footStyles: {
      fillColor: [241, 245, 249],
      textColor: [15, 23, 42],
      fontStyle: 'bold',
    },
    columnStyles: {
      0: { cellWidth: 26 },                     // Waktu
      1: { cellWidth: 24, fontStyle: 'bold' },  // No. Struk
      2: { cellWidth: 16, halign: 'center' },   // Metode (QRIS / CASH)
      3: { cellWidth: 50 },                     // Catatan / Item
      4: { cellWidth: 22, halign: 'right' },    // Gross
      5: { cellWidth: 20, halign: 'right' },    // Potongan
      6: { cellWidth: 24, halign: 'right', fontStyle: 'bold', textColor: [4, 120, 87] }, // Net
    },
    alternateRowStyles: {
      fillColor: [248, 250, 252],
    },
    didParseCell: (data) => {
      // Color payment method badges
      if (data.section === 'body' && data.column.index === 2) {
        if (data.cell.raw === 'QRIS') {
          data.cell.styles.textColor = [2, 132, 199] // sky-600
          data.cell.styles.fontStyle = 'bold'
        } else if (data.cell.raw === 'CASH') {
          data.cell.styles.textColor = [22, 101, 52] // green-800
          data.cell.styles.fontStyle = 'bold'
        }
      }
    },
  })

  // Apply page numbers & footer to all pages
  applyPageFooters(doc)

  // Save PDF
  const boothSlug = slugify(boothNumber || 'Booth')
  const tenantSlug = slugify(tenantName)
  const eventSlug = slugify(eventName)
  doc.save(`Slip_${boothSlug}_${tenantSlug}_${eventSlug}.pdf`)
}

// Re-export alias for flexible imports
export const exportEventSettlementPdf = generateEventSettlementPdf

<template>
  <div class="min-h-screen bg-slate-950 text-slate-100 flex flex-col">

    <!-- Error Banner -->
    <Transition name="slide-down">
      <div v-if="errorMessage" class="fixed top-0 left-0 right-0 z-50 bg-red-600 text-white px-4 py-3 flex items-center justify-between shadow-lg">
        <div class="flex items-center gap-2">
          <AlertCircle class="w-5 h-5 flex-shrink-0" />
          <span class="text-sm font-medium">{{ errorMessage }}</span>
        </div>
        <button @click="errorMessage = ''" class="ml-4 hover:bg-red-700 rounded-lg p-1 transition-colors">
          <X class="w-4 h-4" />
        </button>
      </div>
    </Transition>

    <!-- Success Toast -->
    <Transition name="slide-down">
      <div v-if="successMessage" class="fixed top-0 left-0 right-0 z-50 bg-emerald-600 text-white px-4 py-3 flex items-center justify-between shadow-lg">
        <div class="flex items-center gap-2">
          <CheckCircle class="w-5 h-5 flex-shrink-0" />
          <span class="text-sm font-medium">{{ successMessage }}</span>
        </div>
      </div>
    </Transition>

    <!-- Top Bar -->
    <header class="bg-slate-900 border-b border-slate-800 px-4 py-3 sticky top-0 z-30">
      <div class="max-w-2xl mx-auto flex items-center justify-between gap-3">
        <div class="flex items-center gap-2">
          <ShoppingCart class="w-6 h-6 text-emerald-400" />
          <h1 class="text-lg font-bold tracking-tight text-slate-100">PopUpPOS</h1>
        </div>
        <!-- Event Selector & Admin Nav -->
        <div class="flex items-center gap-2 flex-1 justify-end">
          <CalendarDays class="w-4 h-4 text-slate-400 flex-shrink-0" />
          <select
            v-model="selectedEventId"
            @change="onEventChange"
            class="bg-slate-800 border border-slate-700 text-slate-100 text-sm rounded-xl px-2.5 py-1.5 focus:outline-none focus:ring-2 focus:ring-emerald-500 max-w-[140px] sm:max-w-[180px] truncate"
            :disabled="loadingEvents"
          >
            <option value="">— Pilih Event —</option>
            <option v-for="ev in events" :key="ev.id" :value="ev.id">{{ ev.name }}</option>
          </select>
          <span v-if="loadingEvents" class="text-slate-500 text-xs">loading…</span>

          <router-link
            to="/admin"
            class="flex items-center gap-1.5 bg-slate-800 hover:bg-slate-700 border border-slate-700 hover:border-slate-600 text-slate-300 hover:text-white px-2.5 py-1.5 rounded-xl text-xs font-semibold transition-colors shrink-0"
            title="Ke Dashboard Admin"
          >
            <ShieldCheck class="w-3.5 h-3.5 text-emerald-400" />
            <span>Admin</span>
          </router-link>

          <button
            @click="handleLogout"
            class="flex items-center gap-1.5 bg-slate-800 hover:bg-rose-500/20 text-slate-400 hover:text-rose-400 border border-slate-700 hover:border-rose-500/30 px-2.5 py-1.5 rounded-xl text-xs font-semibold transition-colors shrink-0 cursor-pointer"
            title="Keluar dari akun staf"
          >
            <LogOut class="w-3.5 h-3.5" />
          </button>
        </div>
      </div>
    </header>

    <!-- Main Content -->
    <main class="flex-1 max-w-2xl mx-auto w-full px-4 py-4 flex flex-col gap-4 pb-32">

      <!-- No Event Selected -->
      <div v-if="!selectedEventId" class="flex flex-col items-center justify-center py-20 text-slate-500 gap-3">
        <CalendarDays class="w-12 h-12 text-slate-700" />
        <p class="font-medium">Pilih event untuk memulai</p>
        <p class="text-sm text-slate-600">Pilih event dari dropdown di atas</p>
      </div>

      <template v-else>
        <!-- Tenant Grid -->
        <section>
          <h2 class="text-xs font-semibold uppercase tracking-widest text-slate-500 mb-3">Tenant</h2>
          <div v-if="loadingTenants" class="grid grid-cols-2 sm:grid-cols-3 gap-3">
            <div v-for="i in 6" :key="i" class="h-24 bg-slate-800 rounded-xl animate-pulse" />
          </div>
          <div v-else-if="tenants.length === 0" class="text-center py-10 text-slate-500 text-sm">
            Tidak ada tenant untuk event ini.
          </div>
          <div v-else class="grid grid-cols-2 sm:grid-cols-3 gap-3">
            <button
              v-for="tenant in tenants"
              :key="tenant.id"
              @click="openAddToCart(tenant)"
              class="bg-slate-900 border border-slate-800 hover:border-emerald-500/50 hover:bg-slate-800 rounded-xl p-3 text-left transition-all duration-150 active:scale-95 flex flex-col gap-1.5 group"
            >
              <span class="inline-flex items-center gap-1 bg-slate-800 group-hover:bg-slate-700 rounded-lg px-2 py-0.5 text-xs font-mono text-amber-400 font-semibold w-fit">
                <Hash class="w-3 h-3" />{{ tenant.booth_number || '?' }}
              </span>
              <span class="font-semibold text-slate-100 text-sm leading-tight line-clamp-2">{{ tenant.name }}</span>
              <span class="text-xs text-slate-400">{{ tenant.category || 'Umum' }}</span>
            </button>
          </div>
        </section>

        <!-- Cart Section -->
        <section v-if="cart.length > 0" class="bg-slate-900 border border-slate-800 rounded-2xl p-4 flex flex-col gap-3">
          <div class="flex items-center justify-between">
            <h2 class="text-xs font-semibold uppercase tracking-widest text-slate-500">Keranjang</h2>
            <span class="text-xs text-slate-500">{{ cart.length }} item</span>
          </div>

          <!-- Cart Items -->
          <div class="flex flex-col gap-2">
            <div
              v-for="(item, idx) in cart"
              :key="idx"
              class="flex items-start gap-3 bg-slate-800/60 rounded-xl px-3 py-2.5"
            >
              <div class="flex-1 min-w-0">
                <p class="font-semibold text-slate-100 text-sm truncate">{{ item.tenantName }}</p>
                <p v-if="item.itemNote" class="text-xs text-slate-400 truncate">{{ item.itemNote }}</p>
              </div>
              <div class="flex items-center gap-2 flex-shrink-0">
                <span class="text-emerald-400 font-semibold text-sm">{{ formatRupiah(item.grossAmount) }}</span>
                <button
                  @click="removeFromCart(idx)"
                  class="text-slate-500 hover:text-red-400 transition-colors p-1 rounded-lg hover:bg-red-400/10"
                >
                  <X class="w-4 h-4" />
                </button>
              </div>
            </div>
          </div>

          <!-- Cart Total -->
          <div class="border-t border-slate-800 pt-3 flex items-center justify-between">
            <span class="text-slate-400 font-medium">Total</span>
            <span class="text-2xl font-bold text-emerald-400">{{ formatRupiah(cartTotal) }}</span>
          </div>
        </section>

        <!-- Empty Cart Hint -->
        <section v-else class="bg-slate-900/50 border border-dashed border-slate-800 rounded-2xl p-6 text-center text-slate-600 text-sm">
          <ShoppingCart class="w-8 h-8 mx-auto mb-2 text-slate-700" />
          Tap tenant untuk menambah item ke keranjang
        </section>

        <!-- Checkout Section -->
        <section class="bg-slate-900 border border-slate-800 rounded-2xl p-4 flex flex-col gap-4">
          <h2 class="text-xs font-semibold uppercase tracking-widest text-slate-500">Pembayaran</h2>

          <!-- Payment Method Toggle -->
          <div class="flex gap-2">
            <button
              @click="paymentMethod = 'QRIS'"
              :class="[
                'flex-1 py-2.5 rounded-xl font-semibold text-sm transition-all duration-150 flex items-center justify-center gap-2',
                paymentMethod === 'QRIS'
                  ? 'bg-sky-500 text-white shadow-lg shadow-sky-500/25'
                  : 'bg-slate-800 text-slate-400 hover:bg-slate-700'
              ]"
            >
              <Smartphone class="w-4 h-4" />
              QRIS
            </button>
            <button
              @click="paymentMethod = 'CASH'"
              :class="[
                'flex-1 py-2.5 rounded-xl font-semibold text-sm transition-all duration-150 flex items-center justify-center gap-2',
                paymentMethod === 'CASH'
                  ? 'bg-emerald-500 text-white shadow-lg shadow-emerald-500/25'
                  : 'bg-slate-800 text-slate-400 hover:bg-slate-700'
              ]"
            >
              <Banknote class="w-4 h-4" />
              CASH
            </button>
          </div>

          <!-- Cash Tendered & Change Panel (When CASH is selected) -->
          <div v-if="paymentMethod === 'CASH'" class="bg-slate-800/80 border border-slate-700/80 rounded-xl p-3.5 space-y-3">
            <div class="flex items-center justify-between">
              <span class="text-xs font-semibold text-slate-300 uppercase tracking-wider flex items-center gap-1.5">
                <Banknote class="w-4 h-4 text-emerald-400" />
                Uang Diterima (Cash Tendered)
              </span>
              <button
                type="button"
                @click="setExactCash"
                class="text-xs font-semibold text-emerald-400 bg-emerald-500/10 hover:bg-emerald-500/20 border border-emerald-500/30 rounded-lg px-2.5 py-1 transition-colors cursor-pointer"
              >
                Uang Pas
              </button>
            </div>

            <!-- Input -->
            <div class="relative">
              <span class="absolute left-3.5 top-1/2 -translate-y-1/2 text-sm font-semibold text-slate-400">Rp</span>
              <input
                type="text"
                inputmode="numeric"
                :value="cashTenderedDisplay"
                @input="handleCashTenderedInput"
                :placeholder="cartTotal > 0 ? Number(cartTotal).toLocaleString('id-ID') + ' (Uang Pas)' : '0'"
                class="w-full bg-slate-900 border border-slate-700 focus:border-emerald-500 rounded-xl pl-11 pr-10 py-2.5 text-base font-bold text-slate-100 placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-emerald-500/30 transition-colors"
              />
              <button
                v-if="cashTendered"
                @click="cashTendered = null; cashTenderedDisplay = ''"
                type="button"
                class="absolute right-3 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-200"
              >
                <X class="w-4 h-4" />
              </button>
            </div>

            <!-- Denomination Chips -->
            <div class="grid grid-cols-4 gap-1.5">
              <button
                v-for="chip in [50000, 100000, 200000, 500000]"
                :key="chip"
                type="button"
                @click="addCashTenderedChip(chip)"
                class="py-1.5 text-xs font-semibold rounded-lg bg-slate-900 hover:bg-slate-700/80 border border-slate-700 text-slate-300 hover:text-white transition-all active:scale-95 cursor-pointer"
              >
                +{{ chip >= 1000 ? (chip / 1000) + 'k' : chip }}
              </button>
            </div>

            <!-- Kembalian / Shortage Row -->
            <div class="pt-2 border-t border-slate-700/60 flex items-center justify-between text-xs">
              <span class="text-slate-400 font-medium">Kembalian:</span>
              <div v-if="isCashInsufficient" class="flex items-center gap-1.5 text-rose-400 font-semibold animate-pulse">
                <AlertCircle class="w-3.5 h-3.5" />
                <span>Kurang {{ formatRupiah(cashShortage) }}</span>
              </div>
              <div v-else class="text-right">
                <span class="font-bold text-base text-emerald-400">
                  {{ formatRupiah(cashChange) }}
                </span>
                <span v-if="!cashTendered || cashTendered === cartTotal" class="text-[11px] text-slate-500 block">
                  (Uang Pas)
                </span>
              </div>
            </div>
          </div>

          <!-- Receipt Code -->
          <div class="flex items-center justify-between bg-slate-800/80 border border-slate-700/60 rounded-xl px-4 py-3">
            <div>
              <span class="text-slate-300 text-sm font-semibold block">Kode Struk</span>
              <span class="text-[11px] text-slate-500">Nomor urut otomatis dibuat oleh sistem saat bayar</span>
            </div>
            <div class="flex items-center gap-1.5">
              <span class="font-mono font-bold text-amber-400 tracking-wider text-xs bg-slate-900 border border-slate-700 px-2.5 py-1 rounded-lg">
                AUTO (#)
              </span>
            </div>
          </div>

          <!-- Process Button -->
          <button
            @click="processPayment"
            :disabled="cart.length === 0 || processingPayment || !selectedEventId || isCashInsufficient"
            class="w-full py-4 rounded-xl font-semibold text-base transition-all duration-150 flex items-center justify-center gap-2 bg-emerald-500 hover:bg-emerald-400 text-white shadow-lg shadow-emerald-500/20 disabled:opacity-40 disabled:cursor-not-allowed active:scale-[0.98]"
          >
            <Loader2 v-if="processingPayment" class="w-5 h-5 animate-spin" />
            <CreditCard v-else class="w-5 h-5" />
            {{ processingPayment ? 'Memproses…' : 'Proses Pembayaran' }}
          </button>
        </section>
      </template>
    </main>

    <!-- Recent Transactions Drawer Toggle -->
    <div class="fixed bottom-0 left-0 right-0 z-40">
      <div class="max-w-2xl mx-auto">
        <!-- Toggle Button -->
        <button
          @click="drawerOpen = !drawerOpen"
          class="w-full bg-slate-900 border-t border-slate-800 px-4 py-3 flex items-center justify-between hover:bg-slate-800 transition-colors"
        >
          <div class="flex items-center gap-2">
            <Clock class="w-4 h-4 text-slate-400" />
            <span class="text-sm font-semibold text-slate-300">Transaksi Terbaru</span>
            <span v-if="recentTransactions.length > 0" class="bg-emerald-500/20 text-emerald-400 text-xs font-semibold rounded-full px-2 py-0.5">
              {{ recentTransactions.length }}
            </span>
          </div>
          <ChevronUp :class="['w-4 h-4 text-slate-400 transition-transform duration-200', drawerOpen ? 'rotate-180' : '']" />
        </button>

        <!-- Drawer Content -->
        <Transition name="drawer">
          <div v-if="drawerOpen" class="bg-slate-900 border-t border-slate-800 max-h-96 overflow-y-auto">
            <div v-if="loadingTransactions" class="p-6 text-center text-slate-500 text-sm">
              <Loader2 class="w-5 h-5 animate-spin mx-auto mb-2" />
              Memuat transaksi…
            </div>
            <div v-else-if="!selectedEventId" class="p-6 text-center text-slate-600 text-sm">
              Pilih event untuk melihat transaksi.
            </div>
            <div v-else-if="recentTransactions.length === 0" class="p-6 text-center text-slate-600 text-sm">
              Belum ada transaksi.
            </div>
            <div v-else class="divide-y divide-slate-800">
              <div
                v-for="tx in recentTransactions"
                :key="tx.id"
                class="px-4 py-3 flex items-start gap-3 hover:bg-slate-800/40 transition-colors"
              >
                <div class="flex-1 min-w-0 space-y-2">
                  <div class="flex items-center gap-2 flex-wrap">
                    <button
                      @click="openReceiptModalFromRecent(tx)"
                      class="inline-flex items-center gap-1 font-mono text-sm font-bold text-sky-400 hover:text-sky-300 hover:underline cursor-pointer"
                      title="Lihat Struk Digital"
                    >
                      <Receipt class="w-3.5 h-3.5" />
                      {{ tx.receipt_code }}
                    </button>
                    <span :class="[
                      'text-xs font-semibold rounded-full px-2 py-0.5',
                      tx.payment_method === 'QRIS' ? 'bg-sky-500/20 text-sky-400' : 'bg-emerald-500/20 text-emerald-400'
                    ]">{{ tx.payment_method }}</span>
                    <span :class="[
                      'text-xs font-semibold rounded-full px-2 py-0.5',
                      tx.status === 'COMPLETED' ? 'bg-emerald-500/20 text-emerald-400' : 'bg-red-500/20 text-red-400'
                    ]">{{ tx.status }}</span>
                    <span v-if="tx.void_reason" class="text-[11px] text-red-400 italic">
                      ({{ tx.void_reason }})
                    </span>
                  </div>
                  <div class="flex items-center gap-2 text-xs flex-wrap">
                    <span class="text-sm font-bold text-emerald-400">{{ formatRupiah(tx.total_amount) }}</span>
                    <span class="text-slate-500">•</span>
                    <span class="text-slate-500">{{ formatDate(tx.created_at) }}</span>
                    <span v-if="tx.payment_method === 'CASH' && tx.cash_tendered" class="text-slate-400 font-mono text-[11px]">
                      • Tunai: {{ formatRupiah(tx.cash_tendered) }} (Kembali: {{ formatRupiah(tx.change_amount || 0) }})
                    </span>
                    <span v-if="tx.transaction_items?.length" class="text-slate-500">
                      • {{ tx.transaction_items.length }} item{{ tx.transaction_items.length > 1 ? 's' : '' }}
                    </span>
                  </div>

                  <!-- Item Breakdown List -->
                  <div
                    v-if="tx.transaction_items && tx.transaction_items.length > 0"
                    class="bg-slate-950/60 border border-slate-800/80 rounded-xl p-2.5 space-y-1.5"
                  >
                    <div
                      v-for="item in tx.transaction_items"
                      :key="item.id"
                      class="flex items-start justify-between gap-2 text-xs"
                    >
                      <div class="flex-1 min-w-0">
                        <span class="font-medium text-slate-300">
                          {{ item.tenants?.name || 'Tenant' }}
                          <span v-if="item.tenants?.booth_number" class="text-slate-500 font-mono text-[11px]">
                            ({{ item.tenants.booth_number }})
                          </span>
                        </span>
                        <p v-if="item.item_note" class="text-[11px] text-slate-400 italic truncate">
                          {{ item.item_note }}
                        </p>
                      </div>
                      <span class="font-mono font-medium text-slate-200 shrink-0">
                        {{ formatRupiah(item.gross_amount) }}
                      </span>
                    </div>
                  </div>
                </div>
                <button
                  v-if="tx.status === 'COMPLETED'"
                  @click="openVoidModal(tx)"
                  class="flex-shrink-0 text-xs font-semibold text-red-400 border border-red-400/30 hover:bg-red-400/10 rounded-lg px-2.5 py-1 transition-colors cursor-pointer mt-0.5"
                >
                  VOID
                </button>
              </div>
            </div>
          </div>
        </Transition>
      </div>
    </div>

    <!-- Add to Cart Modal -->
    <Transition name="modal">
      <div v-if="addToCartModal.open" class="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" @click="closeAddToCart" />
        <div class="relative bg-slate-900 border border-slate-800 rounded-2xl w-full max-w-sm shadow-2xl z-10">
          <!-- Modal Header -->
          <div class="flex items-center justify-between px-5 pt-5 pb-3 border-b border-slate-800">
            <div>
              <p class="text-xs text-slate-500 uppercase tracking-widest font-semibold">Tambah ke Keranjang</p>
              <h3 class="font-bold text-slate-100 mt-0.5">{{ addToCartModal.tenant?.name }}</h3>
            </div>
            <button @click="closeAddToCart" class="text-slate-500 hover:text-slate-300 p-1 rounded-lg hover:bg-slate-800 transition-colors">
              <X class="w-5 h-5" />
            </button>
          </div>

          <!-- Modal Body -->
          <div class="p-5 flex flex-col gap-4">
            <!-- Booth info -->
            <div class="flex items-center justify-between text-xs text-slate-400 flex-wrap gap-2">
              <div class="flex items-center gap-2">
                <span class="bg-slate-800 rounded-lg px-2 py-0.5 font-mono text-amber-400 font-semibold">
                  #{{ addToCartModal.tenant?.booth_number || '?' }}
                </span>
                <span>{{ addToCartModal.tenant?.category || 'Umum' }}</span>
              </div>
              <div class="text-[11px] font-medium bg-slate-800/80 rounded-lg px-2 py-1 border border-slate-700/60">
                Split: <span class="text-violet-400 font-semibold">Venue {{ addToCartModal.tenant?.venue_share_percent ?? 10 }}%</span>
                <span class="text-slate-500 mx-1">•</span>
                <span class="text-amber-400 font-semibold">EO {{ addToCartModal.tenant?.organizer_share_percent ?? 0 }}%</span>
                <span class="text-slate-500 mx-1">•</span>
                <span class="text-emerald-400 font-semibold">Tenant {{ Math.max(0, 100 - (Number(addToCartModal.tenant?.venue_share_percent ?? 10) + Number(addToCartModal.tenant?.organizer_share_percent ?? 0))) }}%</span>
              </div>
            </div>

            <!-- Amount Input -->
            <div>
              <label class="text-xs text-slate-500 uppercase tracking-widest font-semibold mb-2 block">Jumlah (Rp)</label>
              <div class="relative">
                <span class="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400 font-semibold text-lg pointer-events-none">Rp</span>
                <input
                  :value="addToCartModal.displayAmount"
                  @input="handleAmountInput"
                  type="text"
                  inputmode="numeric"
                  placeholder="0"
                  class="w-full bg-slate-800 border border-slate-700 focus:border-emerald-500 rounded-xl pl-12 pr-4 py-3 text-2xl font-bold text-slate-100 placeholder-slate-700 focus:outline-none focus:ring-2 focus:ring-emerald-500/30 transition-colors rupiah"
                />
              </div>

              <!-- Quick Add Chips -->
              <div class="flex items-center gap-1.5 flex-wrap mt-2.5">
                <button
                  type="button"
                  @click="addQuickAmount(10000)"
                  class="px-2.5 py-1 text-xs font-semibold rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-300 border border-slate-700 hover:border-slate-600 transition-colors active:scale-95"
                >
                  +10.000
                </button>
                <button
                  type="button"
                  @click="addQuickAmount(25000)"
                  class="px-2.5 py-1 text-xs font-semibold rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-300 border border-slate-700 hover:border-slate-600 transition-colors active:scale-95"
                >
                  +25.000
                </button>
                <button
                  type="button"
                  @click="addQuickAmount(50000)"
                  class="px-2.5 py-1 text-xs font-semibold rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-300 border border-slate-700 hover:border-slate-600 transition-colors active:scale-95"
                >
                  +50.000
                </button>
                <button
                  type="button"
                  @click="addQuickAmount(100000)"
                  class="px-2.5 py-1 text-xs font-semibold rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-300 border border-slate-700 hover:border-slate-600 transition-colors active:scale-95"
                >
                  +100.000
                </button>
                <button
                  type="button"
                  @click="clearAmount"
                  class="px-2.5 py-1 text-xs font-semibold rounded-lg bg-rose-500/10 hover:bg-rose-500/20 text-rose-400 border border-rose-500/30 transition-colors active:scale-95 ml-auto"
                >
                  Clear
                </button>
              </div>
            </div>

            <!-- Note Input -->
            <div>
              <label class="text-xs text-slate-500 uppercase tracking-widest font-semibold mb-2 block">Catatan (Opsional)</label>
              <input
                v-model="addToCartModal.note"
                type="text"
                placeholder="e.g. Nasi Goreng x2"
                class="w-full bg-slate-800 border border-slate-700 focus:border-emerald-500 rounded-xl px-4 py-2.5 text-sm text-slate-100 placeholder-slate-600 focus:outline-none focus:ring-2 focus:ring-emerald-500/30 transition-colors"
              />
            </div>

            <!-- Add Button -->
            <button
              @click="addToCart"
              :disabled="!addToCartModal.amount || addToCartModal.amount <= 0"
              class="w-full py-3.5 rounded-xl font-semibold text-sm bg-emerald-500 hover:bg-emerald-400 text-white transition-all duration-150 disabled:opacity-40 disabled:cursor-not-allowed active:scale-[0.98] flex items-center justify-center gap-2"
            >
              <Plus class="w-4 h-4" />
              Tambah ke Keranjang
            </button>
          </div>
        </div>
      </div>
    </Transition>

    <!-- Void Modal with PIN Authorization -->
    <Transition name="modal">
      <div v-if="voidModal.open" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" @click="closeVoidModal" />
        <div class="relative bg-slate-900 border border-slate-800 rounded-2xl w-full max-w-sm shadow-2xl z-10">
          <div class="flex items-center justify-between px-5 pt-5 pb-3 border-b border-slate-800">
            <div class="flex items-center gap-2 text-rose-400">
              <AlertTriangle class="w-5 h-5 flex-shrink-0" />
              <div>
                <p class="text-xs text-slate-500 uppercase tracking-widest font-semibold">Otorisasi Void Transaksi</p>
                <h3 class="font-bold text-slate-100 mt-0.5">{{ voidModal.transaction?.receipt_code }}</h3>
              </div>
            </div>
            <button @click="closeVoidModal" class="text-slate-500 hover:text-slate-300 p-1 rounded-lg hover:bg-slate-800 transition-colors">
              <X class="w-5 h-5" />
            </button>
          </div>
          <div class="p-5 flex flex-col gap-4">
            <p class="text-xs text-slate-400">
              Transaksi sebesar <strong class="text-rose-400">{{ formatRupiah(voidModal.transaction?.total_amount) }}</strong> akan di-void. Membutuhkan verifikasi supervisor.
            </p>

            <!-- Supervisor PIN -->
            <div>
              <label class="text-xs text-slate-400 uppercase tracking-wider font-semibold mb-1.5 flex items-center gap-1.5">
                <Lock class="w-3.5 h-3.5 text-amber-400" />
                <span>PIN Supervisor / Admin</span>
                <span class="text-rose-400">*</span>
              </label>
              <input
                v-model="voidModal.pin"
                type="password"
                maxlength="6"
                inputmode="numeric"
                placeholder="Masukkan 6-digit PIN"
                class="w-full bg-slate-800 border border-slate-700 focus:border-rose-500 rounded-xl px-4 py-2.5 text-center text-lg font-mono tracking-widest text-slate-100 placeholder-slate-600 focus:outline-none focus:ring-2 focus:ring-rose-500/30 transition-colors"
                @keydown.enter="confirmVoid"
              />
              <p v-if="voidModal.pinError" class="text-xs text-rose-400 mt-1 flex items-center gap-1">
                <AlertCircle class="w-3 h-3" />
                {{ voidModal.pinError }}
              </p>
            </div>

            <!-- Void Reason -->
            <div>
              <label class="text-xs text-slate-400 uppercase tracking-wider font-semibold mb-1.5 block">
                Alasan Void <span class="text-rose-400">*</span>
              </label>
              <textarea
                v-model="voidModal.reason"
                placeholder="Contoh: Salah nominal, pembeli membatalkan pesanan…"
                rows="2"
                class="w-full bg-slate-800 border border-slate-700 focus:border-rose-500 rounded-xl px-3.5 py-2 text-xs text-slate-100 placeholder-slate-600 focus:outline-none focus:ring-2 focus:ring-rose-500/30 transition-colors resize-none"
              />
            </div>

            <div class="flex gap-2 pt-1">
              <button
                type="button"
                @click="closeVoidModal"
                class="flex-1 py-2.5 rounded-xl font-semibold text-xs bg-slate-800 text-slate-300 hover:bg-slate-700 transition-colors"
              >
                Batal
              </button>
              <button
                type="button"
                @click="confirmVoid"
                :disabled="!voidModal.reason.trim() || !voidModal.pin || voidModal.pin.length < 6 || voidModal.processing"
                class="flex-1 py-2.5 rounded-xl font-semibold text-xs bg-red-600 hover:bg-red-500 text-white transition-all duration-150 disabled:opacity-40 disabled:cursor-not-allowed flex items-center justify-center gap-2 cursor-pointer shadow-lg shadow-red-600/20"
              >
                <Loader2 v-if="voidModal.processing" class="w-4 h-4 animate-spin" />
                <XCircle v-else class="w-4 h-4" />
                Konfirmasi Void
              </button>
            </div>
          </div>
        </div>
      </div>
    </Transition>

    <!-- Digital Receipt Modal -->
    <Transition name="modal">
      <div v-if="receiptModal.open" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" @click="receiptModal.open = false" />
        <div class="relative bg-slate-900 border border-slate-800 rounded-2xl w-full max-w-md shadow-2xl z-10 overflow-hidden">
          <!-- Modal Header -->
          <div class="flex items-center justify-between px-5 py-3.5 border-b border-slate-800 bg-slate-800/40">
            <div class="flex items-center gap-2">
              <div class="w-7 h-7 rounded-lg bg-emerald-500/10 border border-emerald-500/20 flex items-center justify-center text-emerald-400">
                <Receipt class="w-4 h-4" />
              </div>
              <div>
                <h3 class="font-bold text-slate-100 text-sm">Struk Digital</h3>
                <p class="text-[11px] text-slate-400">Bukti Pembayaran Transaksi</p>
              </div>
            </div>
            <button
              @click="receiptModal.open = false"
              class="text-slate-400 hover:text-slate-200 p-1 rounded-lg hover:bg-slate-800 transition-colors"
            >
              <X class="w-5 h-5" />
            </button>
          </div>

          <!-- Receipt Paper Card -->
          <div class="p-5 space-y-4 max-h-[75vh] overflow-y-auto">
            <div class="bg-slate-950/80 border border-slate-800 rounded-xl p-4 font-mono text-xs text-slate-300 space-y-3">
              <!-- Receipt Header Info -->
              <div class="text-center pb-3 border-b border-dashed border-slate-800 space-y-1">
                <h4 class="font-sans font-black text-sm tracking-widest text-slate-100 uppercase">Nyaris Pop-Up POS</h4>
                <p v-if="receiptModal.transaction?.event_name" class="text-slate-400 font-sans text-xs">
                  {{ receiptModal.transaction.event_name }}
                </p>
                <p class="text-amber-400 text-xs font-bold pt-1">
                  #{{ receiptModal.transaction?.receipt_code }}
                </p>
                <div class="text-[11px] text-slate-500 pt-0.5">
                  {{ formatDate(receiptModal.transaction?.created_at) }}
                </div>
                <div class="inline-block mt-1">
                  <span :class="[
                    'text-[10px] font-bold px-2 py-0.5 rounded-full uppercase tracking-wider',
                    receiptModal.transaction?.payment_method === 'QRIS'
                      ? 'bg-sky-500/20 text-sky-400 border border-sky-500/30'
                      : 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/30'
                  ]">
                    {{ receiptModal.transaction?.payment_method }}
                  </span>
                </div>
              </div>

              <!-- Purchased Items Breakdown -->
              <div class="space-y-2 py-1">
                <div
                  v-for="(item, idx) in receiptModal.items"
                  :key="idx"
                  class="flex justify-between items-start gap-2"
                >
                  <div class="min-w-0 flex-1">
                    <div class="text-slate-200 font-semibold truncate">
                      {{ item.tenantName }}
                      <span v-if="item.boothNumber" class="text-slate-500 text-[10px]">({{ item.boothNumber }})</span>
                    </div>
                    <div v-if="item.itemNote" class="text-[10px] text-slate-500 italic truncate">
                      {{ item.itemNote }}
                    </div>
                  </div>
                  <div class="font-bold text-slate-200 shrink-0">
                    {{ formatRupiah(item.grossAmount) }}
                  </div>
                </div>
              </div>

              <!-- Totals & Payment Details -->
              <div class="pt-3 border-t border-dashed border-slate-800 space-y-1.5">
                <div class="flex justify-between text-sm font-bold text-slate-100">
                  <span>TOTAL</span>
                  <span class="text-emerald-400">{{ formatRupiah(receiptModal.transaction?.total_amount) }}</span>
                </div>

                <!-- Cash Tendered & Change -->
                <template v-if="receiptModal.transaction?.payment_method === 'CASH'">
                  <div class="flex justify-between text-slate-400 text-xs pt-1">
                    <span>Uang Diterima</span>
                    <span>{{ formatRupiah(receiptModal.transaction?.cash_tendered || receiptModal.transaction?.total_amount) }}</span>
                  </div>
                  <div class="flex justify-between text-xs font-semibold text-emerald-400">
                    <span>Kembalian</span>
                    <span>{{ formatRupiah(receiptModal.transaction?.change_amount || 0) }}</span>
                  </div>
                </template>
              </div>

              <!-- Footer note -->
              <div class="text-center pt-3 border-t border-dashed border-slate-800 text-[10px] text-slate-500">
                Terima kasih telah berbelanja!
              </div>
            </div>

            <!-- Action Buttons -->
            <div class="flex gap-2.5">
              <button
                type="button"
                @click="copyReceiptText"
                class="flex-1 py-2.5 rounded-xl font-semibold text-xs transition-all duration-150 flex items-center justify-center gap-1.5 bg-slate-800 hover:bg-slate-700 text-slate-200 border border-slate-700 active:scale-95 cursor-pointer"
              >
                <Check v-if="receiptModal.copied" class="w-4 h-4 text-emerald-400" />
                <Copy v-else class="w-4 h-4" />
                {{ receiptModal.copied ? 'Disalin!' : 'Copy Text' }}
              </button>
              <button
                type="button"
                @click="receiptModal.open = false"
                class="px-5 py-2.5 rounded-xl font-semibold text-xs bg-emerald-500 hover:bg-emerald-400 text-slate-950 transition-all duration-150 active:scale-95 cursor-pointer"
              >
                Selesai
              </button>
            </div>
          </div>
        </div>
      </div>
    </Transition>

  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import {
  ShoppingCart, CalendarDays, Hash, X, Plus, CreditCard, Clock,
  ChevronUp, AlertCircle, CheckCircle, Loader2, RefreshCw,
  Smartphone, Banknote, AlertTriangle, XCircle, ShieldCheck,
  Receipt, Copy, Check, LogOut, Lock
} from 'lucide-vue-next'
import { supabase } from '@/lib/supabase.js'
import { useAuth } from '@/lib/useAuth.js'
import { formatRupiah } from '@/lib/currency.js'

const router = useRouter()
const { signOut } = useAuth()

async function handleLogout() {
  await signOut()
  router.push('/login')
}

// ─── State ────────────────────────────────────────────────────────────────────

const errorMessage = ref('')
const successMessage = ref('')
const loadingEvents = ref(false)
const loadingTenants = ref(false)
const loadingTransactions = ref(false)
const processingPayment = ref(false)
let checkoutInFlight = false

const events = ref([])
const selectedEventId = ref('')
const tenants = ref([])
const recentTransactions = ref([])

const cart = ref([])
const paymentMethod = ref('QRIS')
const receiptCode = ref('AUTO')

const cashTendered = ref(null)
const cashTenderedDisplay = ref('')

const receiptModal = ref({
  open: false,
  transaction: null,
  items: [],
  copied: false
})

const drawerOpen = ref(false)

let realtimeChannel = null

// ─── Add to Cart Modal ────────────────────────────────────────────────────────

const addToCartModal = ref({
  open: false,
  tenant: null,
  amount: null,
  displayAmount: '',
  note: ''
})

function openAddToCart(tenant) {
  addToCartModal.value = {
    open: true,
    tenant,
    amount: null,
    displayAmount: '',
    note: ''
  }
}

function handleAmountInput(e) {
  const raw = e.target.value.replace(/\D/g, '')
  if (!raw) {
    addToCartModal.value.amount = null
    addToCartModal.value.displayAmount = ''
    return
  }
  const numeric = parseInt(raw, 10)
  addToCartModal.value.amount = numeric
  addToCartModal.value.displayAmount = Number(numeric).toLocaleString('id-ID')
}

function addQuickAmount(delta) {
  const current = addToCartModal.value.amount || 0
  const updated = current + delta
  addToCartModal.value.amount = updated
  addToCartModal.value.displayAmount = Number(updated).toLocaleString('id-ID')
}

function clearAmount() {
  addToCartModal.value.amount = null
  addToCartModal.value.displayAmount = ''
}

function closeAddToCart() {
  addToCartModal.value.open = false
}

function addToCart() {
  const { tenant, amount, note } = addToCartModal.value
  if (!amount || amount <= 0) return
  const venueShare = Number(tenant.venue_share_percent ?? 10)
  const orgShare = Number(tenant.organizer_share_percent ?? 0)
  const totalShare = venueShare + orgShare
  cart.value.push({
    tenantId: tenant.id,
    tenantName: tenant.name,
    sharePercent: totalShare || tenant.share_percent || 10,
    venueSharePercent: venueShare,
    organizerSharePercent: orgShare,
    grossAmount: amount,
    itemNote: note.trim()
  })
  closeAddToCart()
}

function removeFromCart(index) {
  cart.value.splice(index, 1)
}

// ─── Void Modal with Supervisor PIN ──────────────────────────────────────────

const ADMIN_PIN = import.meta.env.VITE_ADMIN_PIN || '000000'

const voidModal = ref({
  open: false,
  transaction: null,
  reason: '',
  pin: '',
  pinError: '',
  processing: false
})

function openVoidModal(tx) {
  voidModal.value = {
    open: true,
    transaction: tx,
    reason: '',
    pin: '',
    pinError: '',
    processing: false
  }
}

function closeVoidModal() {
  voidModal.value = {
    open: false,
    transaction: null,
    reason: '',
    pin: '',
    pinError: '',
    processing: false
  }
}

async function confirmVoid() {
  const { transaction, reason, pin } = voidModal.value
  if (!reason.trim()) return
  if (pin !== ADMIN_PIN) {
    voidModal.value.pinError = 'PIN Supervisor / Admin salah!'
    return
  }
  voidModal.value.pinError = ''
  voidModal.value.processing = true
  try {
    const { error } = await supabase
      .from('transactions')
      .update({
        status: 'VOIDED',
        void_reason: reason.trim(),
        voided_at: new Date().toISOString()
      })
      .eq('id', transaction.id)
    if (error) throw error
    showSuccess('Transaksi berhasil di-void.')
    closeVoidModal()
    await fetchRecentTransactions()
  } catch (err) {
    showError('Gagal void transaksi: ' + err.message)
  } finally {
    voidModal.value.processing = false
  }
}

// ─── Computed ─────────────────────────────────────────────────────────────────

const cartTotal = computed(() => cart.value.reduce((sum, i) => sum + i.grossAmount, 0))

// ─── Cash Tendered & Change Calculations ─────────────────────────────────────

const isCashInsufficient = computed(() => {
  return paymentMethod.value === 'CASH' && cashTendered.value !== null && cashTendered.value > 0 && cashTendered.value < cartTotal.value
})

const cashChange = computed(() => {
  if (paymentMethod.value !== 'CASH') return 0
  const tendered = (cashTendered.value === null || cashTendered.value === 0) ? cartTotal.value : cashTendered.value
  return Math.max(0, tendered - cartTotal.value)
})

const cashShortage = computed(() => {
  if (paymentMethod.value !== 'CASH') return 0
  if (cashTendered.value && cashTendered.value < cartTotal.value) {
    return cartTotal.value - cashTendered.value
  }
  return 0
})

function handleCashTenderedInput(e) {
  const raw = e.target.value.replace(/\D/g, '')
  if (!raw) {
    cashTendered.value = null
    cashTenderedDisplay.value = ''
    return
  }
  const numeric = parseInt(raw, 10)
  cashTendered.value = numeric
  cashTenderedDisplay.value = Number(numeric).toLocaleString('id-ID')
}

function setExactCash() {
  if (cartTotal.value <= 0) return
  cashTendered.value = cartTotal.value
  cashTenderedDisplay.value = Number(cartTotal.value).toLocaleString('id-ID')
}

function addCashTenderedChip(delta) {
  const current = cashTendered.value || 0
  const updated = current + delta
  cashTendered.value = updated
  cashTenderedDisplay.value = Number(updated).toLocaleString('id-ID')
}

// ─── Digital Receipt Modal Helpers ───────────────────────────────────────────

function openReceiptModalFromRecent(tx) {
  const currentEv = events.value.find(e => e.id === selectedEventId.value)
  receiptModal.value = {
    open: true,
    transaction: {
      id: tx.id,
      receipt_code: tx.receipt_code,
      event_name: currentEv?.name || '',
      payment_method: tx.payment_method,
      total_amount: tx.total_amount,
      cash_tendered: tx.cash_tendered,
      change_amount: tx.change_amount,
      created_at: tx.created_at,
      status: tx.status
    },
    items: (tx.transaction_items || []).map(ti => ({
      tenantName: ti.tenants?.name || 'Tenant',
      boothNumber: ti.tenants?.booth_number || '',
      grossAmount: ti.gross_amount,
      itemNote: ti.item_note
    })),
    copied: false
  }
}

function copyReceiptText() {
  if (!receiptModal.value.transaction) return
  const tx = receiptModal.value.transaction
  const items = receiptModal.value.items || []
  const sep = '--------------------------------'
  const dSep = '================================'

  let text = `${dSep}\n       NYARIS POP-UP POS\n${dSep}\n`
  if (tx.event_name) text += `Event   : ${tx.event_name}\n`
  text += `No Struk: ${tx.receipt_code}\n`
  text += `Waktu   : ${formatDate(tx.created_at)}\n`
  text += `Metode  : ${tx.payment_method}\n`
  text += `${sep}\n`

  items.forEach(it => {
    const boothStr = it.boothNumber ? ` (${it.boothNumber})` : ''
    text += `${it.tenantName}${boothStr}\n`
    text += `  ${formatRupiah(it.grossAmount)}${it.itemNote ? ' - ' + it.itemNote : ''}\n`
  })

  text += `${sep}\n`
  text += `TOTAL        : ${formatRupiah(tx.total_amount)}\n`
  if (tx.payment_method === 'CASH' && tx.cash_tendered != null) {
    text += `Uang Diterima: ${formatRupiah(tx.cash_tendered)}\n`
    text += `Kembalian    : ${formatRupiah(tx.change_amount || 0)}\n`
  }
  text += `${dSep}\nTerima kasih telah berbelanja!\n`

  navigator.clipboard.writeText(text)
  receiptModal.value.copied = true
  showSuccess('Teks struk berhasil disalin!')
  setTimeout(() => { receiptModal.value.copied = false }, 3000)
}

// ─── Notifications ────────────────────────────────────────────────────────────

function showError(msg) {
  successMessage.value = ''
  errorMessage.value = msg
  setTimeout(() => { errorMessage.value = '' }, 5000)
}

function showSuccess(msg) {
  errorMessage.value = ''
  successMessage.value = msg
  setTimeout(() => { successMessage.value = '' }, 3000)
}

// ─── Data Fetching ────────────────────────────────────────────────────────────

async function fetchEvents() {
  loadingEvents.value = true
  try {
    const { data, error } = await supabase
      .from('events')
      .select('id, name, is_active')
      .order('created_at', { ascending: false })
    if (error) throw error
    events.value = data || []
    // Auto-select the first active event
    const active = events.value.find(e => e.is_active)
    if (active && !selectedEventId.value) {
      selectedEventId.value = active.id
      await onEventChange()
    }
  } catch (err) {
    showError('Gagal memuat events: ' + err.message)
  } finally {
    loadingEvents.value = false
  }
}

async function fetchTenants() {
  if (!selectedEventId.value) { tenants.value = []; return }
  loadingTenants.value = true
  try {
    const { data, error } = await supabase
      .from('tenants')
      .select('id, name, category, booth_number, share_percent, venue_share_percent, organizer_share_percent')
      .eq('event_id', selectedEventId.value)
      .order('booth_number', { ascending: true })
    if (error) throw error
    tenants.value = data || []
  } catch (err) {
    showError('Gagal memuat tenant: ' + err.message)
  } finally {
    loadingTenants.value = false
  }
}

async function fetchRecentTransactions() {
  if (!selectedEventId.value) { recentTransactions.value = []; return }
  loadingTransactions.value = true
  try {
    const { data, error } = await supabase
      .from('transactions')
      .select(`
        id,
        receipt_code,
        payment_method,
        total_amount,
        cash_tendered,
        change_amount,
        status,
        void_reason,
        voided_at,
        created_at,
        transaction_items (
          id,
          gross_amount,
          item_note,
          tenants (
            id,
            name,
            booth_number
          )
        )
      `)
      .eq('event_id', selectedEventId.value)
      .order('created_at', { ascending: false })
      .limit(10)
    if (error) throw error
    recentTransactions.value = data || []
  } catch (err) {
    showError('Gagal memuat transaksi: ' + err.message)
  } finally {
    loadingTransactions.value = false
  }
}

// ─── Event Change ─────────────────────────────────────────────────────────────

async function onEventChange() {
  cart.value = []
  receiptCode.value = 'AUTO'
  await Promise.all([fetchTenants(), fetchRecentTransactions()])
  subscribeRealtime()
}

// ─── Realtime Subscription ────────────────────────────────────────────────────

function subscribeRealtime() {
  if (realtimeChannel) {
    supabase.removeChannel(realtimeChannel)
    realtimeChannel = null
  }
  if (!selectedEventId.value) return

  realtimeChannel = supabase
    .channel(`transactions:event:${selectedEventId.value}`)
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'transactions',
        filter: `event_id=eq.${selectedEventId.value}`
      },
      () => { fetchRecentTransactions() }
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'transaction_items',
      },
      () => { fetchRecentTransactions() }
    )
    .subscribe()
}

// ─── Payment Processing ───────────────────────────────────────────────────────

function getClientTxId() {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID()
  }
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0
    const v = c === 'x' ? r : (r & 0x3) | 0x8
    return v.toString(16)
  })
}

async function processPayment() {
  // Synchronous lock: instantaneous block before any await to prevent double-tap race conditions
  if (checkoutInFlight) return
  if (cart.value.length === 0 || !selectedEventId.value || isCashInsufficient.value) return

  checkoutInFlight = true
  processingPayment.value = true

  try {
    let recordedCashTendered = null
    let recordedChange = null
    if (paymentMethod.value === 'CASH') {
      recordedCashTendered = (cashTendered.value && cashTendered.value >= cartTotal.value)
        ? cashTendered.value
        : cartTotal.value
      recordedChange = recordedCashTendered - cartTotal.value
    }

    // Generate unique client idempotency key for this checkout attempt
    const clientTxId = getClientTxId()

    // 1. Insert transaction with automatic sequential receipt code and client idempotency key
    let txData = null
    const { data: insertedTx, error: txError } = await supabase
      .from('transactions')
      .insert({
        event_id: selectedEventId.value,
        receipt_code: 'AUTO',
        client_tx_id: clientTxId,
        payment_method: paymentMethod.value,
        total_amount: cartTotal.value,
        cash_tendered: recordedCashTendered,
        change_amount: recordedChange,
        status: 'COMPLETED'
      })
      .select('id, receipt_code, created_at')
      .single()

    if (txError) {
      // Duplicate Recovery: if client_tx_id unique constraint was violated (code 23505)
      // during a retry or slow network recovery, retrieve the already-created transaction
      if (txError.code === '23505') {
        const { data: existingTx, error: fetchErr } = await supabase
          .from('transactions')
          .select('id, receipt_code, created_at')
          .eq('client_tx_id', clientTxId)
          .single()
        if (fetchErr || !existingTx) throw txError
        txData = existingTx
      } else {
        throw txError
      }
    } else {
      txData = insertedTx
    }

    const transactionId = txData.id

    // 2. Insert transaction items if not already inserted
    const { data: existingItems } = await supabase
      .from('transaction_items')
      .select('id')
      .eq('transaction_id', transactionId)
      .limit(1)

    if (!existingItems || existingItems.length === 0) {
      const items = cart.value.map(item => ({
        transaction_id: transactionId,
        tenant_id: item.tenantId,
        item_note: item.itemNote || null,
        gross_amount: item.grossAmount,
        share_percent: item.sharePercent,
        venue_share_percent: item.venueSharePercent ?? 0,
        organizer_share_percent: item.organizerSharePercent ?? 0
      }))

      const { error: itemsError } = await supabase
        .from('transaction_items')
        .insert(items)
      if (itemsError) throw itemsError
    }

    // 3. Prepare receipt data before clearing cart
    const activeEv = events.value.find(e => e.id === selectedEventId.value)
    const completedItems = [...cart.value]
    const completedCode = txData.receipt_code || 'POS-0001'
    const completedTx = {
      id: transactionId,
      receipt_code: completedCode,
      event_name: activeEv?.name || '',
      payment_method: paymentMethod.value,
      total_amount: cartTotal.value,
      cash_tendered: recordedCashTendered,
      change_amount: recordedChange,
      created_at: txData.created_at || new Date().toISOString()
    }

    // Clear cart + reset cash + keep auto indicator
    cart.value = []
    cashTendered.value = null
    cashTenderedDisplay.value = ''
    receiptCode.value = 'AUTO'

    // Open Digital Receipt Modal
    receiptModal.value = {
      open: true,
      transaction: completedTx,
      items: completedItems,
      copied: false
    }

    showSuccess(`Pembayaran berhasil! Struk: ${completedCode}`)
    await fetchRecentTransactions()
  } catch (err) {
    const isNetworkErr = !navigator.onLine ||
      err.message?.includes('Failed to fetch') ||
      err.message?.includes('NetworkError') ||
      err.message?.includes('network') ||
      err.message?.includes('fetch')
    const msg = isNetworkErr
      ? 'Koneksi terganggu. Transaksi belum tersimpan, silakan coba lagi.'
      : ('Gagal memproses pembayaran: ' + (err.message || 'Terjadi kesalahan'))
    showError(msg)
  } finally {
    checkoutInFlight = false
    processingPayment.value = false
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function formatDate(isoString) {
  if (!isoString) return ''
  const d = new Date(isoString)
  return d.toLocaleString('id-ID', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })
}

// ─── Lifecycle ────────────────────────────────────────────────────────────────

onMounted(async () => {
  await fetchEvents()
})

onUnmounted(() => {
  if (realtimeChannel) {
    supabase.removeChannel(realtimeChannel)
  }
})
</script>

<style scoped>
/* Slide down transition for banners */
.slide-down-enter-active,
.slide-down-leave-active {
  transition: all 0.3s ease;
}
.slide-down-enter-from,
.slide-down-leave-to {
  transform: translateY(-100%);
  opacity: 0;
}

/* Modal transition */
.modal-enter-active,
.modal-leave-active {
  transition: opacity 0.25s ease;
}
.modal-enter-from,
.modal-leave-to {
  opacity: 0;
}

/* Drawer transition */
.drawer-enter-active,
.drawer-leave-active {
  transition: all 0.25s ease;
  overflow: hidden;
}
.drawer-enter-from,
.drawer-leave-to {
  max-height: 0 !important;
  opacity: 0;
}
.drawer-enter-to,
.drawer-leave-from {
  max-height: 384px;
}
</style>

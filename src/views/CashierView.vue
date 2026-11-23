<template>
  <div class="min-h-screen bg-light-surface text-light-on-surface flex flex-col">

    <!-- Error Banner -->
    <Transition name="slide-down">
      <div v-if="errorMessage" class="fixed top-16 left-0 right-0 z-50 bg-light-error text-light-on-error px-4 py-3 flex items-center justify-between shadow-lg">
        <div class="flex items-center gap-2">
          <AlertCircle class="w-5 h-5 flex-shrink-0" />
          <span class="text-sm font-medium">{{ errorMessage }}</span>
        </div>
        <button @click="errorMessage = ''" class="ml-4 hover:bg-black/10 rounded-lg p-1 transition-colors">
          <X class="w-4 h-4" />
        </button>
      </div>
    </Transition>

    <!-- Success Toast -->
    <Transition name="slide-down">
      <div v-if="successMessage" class="fixed top-16 left-0 right-0 z-50 bg-light-secondary-container text-light-on-secondary-container px-4 py-3 flex items-center justify-between shadow-lg">
        <div class="flex items-center gap-2">
          <CheckCircle class="w-5 h-5 flex-shrink-0" />
          <span class="text-sm font-medium">{{ successMessage }}</span>
        </div>
      </div>
    </Transition>

    <!-- Mobile compact header (only shown on mobile, GlobalNavigation handles desktop top nav) -->
    <header class="lg:hidden sticky top-0 z-30 bg-light-surface-container-lowest border-b border-light-outline-variant px-4 py-3 flex items-center justify-between gap-3">
      <div class="flex items-center gap-2 min-w-0">
        <ShoppingCart class="w-5 h-5 text-light-primary flex-shrink-0" />
        <span class="font-display font-bold text-light-on-surface text-sm truncate">
          {{ events.find(e => e.id === selectedEventId)?.name || 'PopUpPOS' }}
        </span>
      </div>
      <div class="flex items-center gap-2 shrink-0">
        <button
          @click="drawerOpen = !drawerOpen"
          class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-md border border-light-outline-variant bg-light-surface-container-low text-light-on-surface-variant text-xs font-label font-semibold transition-colors hover:bg-light-surface-container"
        >
          <Clock class="w-3.5 h-3.5" />
          <span>Riwayat Struk</span>
        </button>
      </div>
    </header>

    <!-- Main workspace -->
    <div class="flex-1 flex flex-col lg:flex-row min-h-0">

      <!-- No Event Selected -->
      <div v-if="!selectedEventId" class="flex-1 flex flex-col items-center justify-center py-20 gap-6 text-center px-6">
        <div class="w-16 h-16 rounded-full bg-light-surface-container-low border border-light-outline-variant flex items-center justify-center">
          <CalendarDays class="w-8 h-8 text-light-on-surface-variant" />
        </div>
        <div class="space-y-2">
          <p class="font-display font-semibold text-light-on-surface text-lg">
            {{ events.length === 0 ? 'Tidak ada event aktif' : 'Pilih event untuk memulai' }}
          </p>
          <p class="text-sm text-light-on-surface-variant max-w-xs">
            {{ events.length === 0
              ? 'Aktifkan event di menu Admin agar kasir dapat memproses transaksi.'
              : 'Pilih event dari menu navigasi atas untuk memuat lineup tenant.' }}
          </p>
        </div>
        <router-link
          v-if="events.length === 0"
          to="/admin"
          class="inline-flex items-center gap-2 bg-light-primary text-light-on-primary px-5 py-2.5 rounded-md text-sm font-label font-semibold transition-colors hover:opacity-90 active:scale-[0.98]"
        >
          <ShieldCheck class="w-4 h-4" />
          <span>Buka Dashboard Admin</span>
        </router-link>
      </div>

      <!-- Active event workspace: 2-col grid on desktop -->
      <template v-else>
        <div class="flex-1 min-w-0 grid grid-cols-1 lg:grid-cols-[1fr_430px]">

          <!-- LEFT COLUMN: Step 1 — Pilih Booth -->
          <main class="p-4 lg:p-6 flex flex-col gap-5 min-w-0 pb-32 lg:pb-6">

            <!-- Section header (desktop only) -->
            <div class="hidden lg:flex items-center justify-between gap-3">
              <div class="flex items-center gap-3">
                <span class="inline-flex items-center justify-center w-7 h-7 rounded-full bg-light-primary text-light-on-primary text-xs font-bold font-label flex-shrink-0">1</span>
                <h2 class="font-display font-semibold text-light-on-surface text-base">Pilih Booth</h2>
              </div>
              <button
                @click="drawerOpen = !drawerOpen"
                class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-md border border-light-outline-variant bg-light-surface-container-lowest text-light-on-surface-variant text-xs font-label font-semibold transition-colors hover:bg-light-surface-container"
              >
                <Clock class="w-3.5 h-3.5" />
                <span>Riwayat Struk</span>
                <span v-if="recentTransactions.length > 0" class="inline-flex items-center justify-center w-4 h-4 rounded-full bg-light-primary text-light-on-primary text-[10px] font-bold">
                  {{ recentTransactions.length > 9 ? '9+' : recentTransactions.length }}
                </span>
              </button>
            </div>

            <!-- Search + Category Pills -->
            <div v-if="tenants.length > 0 && !loadingTenants" class="flex flex-col gap-3">
              <!-- Search input -->
              <div class="relative">
                <Search class="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-light-on-surface-variant pointer-events-none" />
                <input
                  v-model="tenantSearchQuery"
                  type="text"
                  placeholder="Cari nama brand atau nomor booth..."
                  class="w-full bg-light-surface-container-lowest border border-light-outline-variant focus:border-light-primary text-light-on-surface placeholder-light-on-surface-variant rounded-md pl-9 pr-9 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-light-primary/20 transition-all"
                />
                <button
                  v-if="tenantSearchQuery"
                  type="button"
                  @click="tenantSearchQuery = ''"
                  class="absolute right-2.5 top-1/2 -translate-y-1/2 p-1 text-light-on-surface-variant hover:text-light-on-surface rounded-md transition-colors cursor-pointer"
                  title="Hapus pencarian"
                >
                  <X class="w-3.5 h-3.5" />
                </button>
              </div>

              <!-- Category filter pills -->
              <div
                v-if="availableTenantCategories.length > 2"
                class="flex items-center gap-2 overflow-x-auto no-scrollbar py-0.5"
              >
                <button
                  v-for="cat in availableTenantCategories"
                  :key="cat"
                  type="button"
                  @click="selectedTenantCategory = cat"
                  :class="selectedTenantCategory === cat
                    ? 'bg-light-primary text-light-on-primary'
                    : 'bg-light-surface-container-lowest border border-light-outline-variant text-light-on-surface-variant hover:bg-light-surface-container-low'"
                  class="inline-flex items-center px-4 py-1.5 rounded-full font-label text-xs whitespace-nowrap transition-colors cursor-pointer shrink-0 active:scale-95"
                >
                  {{ cat === 'ALL' ? 'Semua' : cat }}
                </button>
              </div>
            </div>

            <!-- Loading Skeleton -->
            <div v-if="loadingTenants" class="grid grid-cols-2 md:grid-cols-3 gap-3">
              <div v-for="i in 6" :key="i" class="h-28 bg-light-surface-container-high rounded-md animate-pulse" />
            </div>

            <!-- Empty: no tenants -->
            <div v-else-if="tenants.length === 0" class="flex flex-col items-center justify-center py-12 gap-3 text-center">
              <div class="w-12 h-12 rounded-full bg-light-surface-container-low border border-light-outline-variant flex items-center justify-center">
                <Hash class="w-6 h-6 text-light-on-surface-variant" />
              </div>
              <p class="text-sm text-light-on-surface-variant">Tidak ada tenant untuk event ini.</p>
            </div>

            <!-- Empty: filter returns 0 -->
            <div
              v-else-if="filteredTenants.length === 0"
              class="flex flex-col items-center justify-center py-12 gap-3 text-center border border-dashed border-light-outline-variant rounded-md bg-light-surface-container-low"
            >
              <Search class="w-8 h-8 text-light-on-surface-variant" />
              <div class="space-y-1">
                <p class="text-sm font-semibold text-light-on-surface">Tidak ada tenant yang cocok.</p>
                <p class="text-xs text-light-on-surface-variant">Coba kata kunci lain atau reset filter.</p>
              </div>
              <button
                type="button"
                @click="tenantSearchQuery = ''; selectedTenantCategory = 'ALL'"
                class="inline-flex items-center gap-1.5 bg-light-surface-container-lowest border border-light-outline-variant text-light-primary px-3.5 py-1.5 rounded-md text-xs font-label font-semibold transition-colors cursor-pointer hover:bg-light-surface-container-low"
              >
                <RefreshCw class="w-3 h-3" />
                <span>Reset Filter</span>
              </button>
            </div>

            <!-- Tenant Grid -->
            <div v-else class="grid grid-cols-2 md:grid-cols-3 gap-3">
              <button
                v-for="tenant in filteredTenants"
                :key="tenant.id"
                @click="openAddToCart(tenant)"
                class="flex flex-col justify-between gap-3 p-4 rounded-md bg-light-surface-container-lowest border border-light-outline-variant hover:border-light-primary hover:bg-light-surface-container-low text-left transition-colors duration-150 active:scale-[0.98] cursor-pointer"
              >
                <div class="flex items-start justify-between gap-2">
                  <span class="font-mono text-xs px-2 py-0.5 rounded-sm bg-light-surface-container text-light-on-surface tabular-nums">
                    #{{ tenant.booth_number || '?' }}
                  </span>
                </div>
                <div class="flex flex-col gap-1">
                  <span class="font-display font-semibold text-light-on-surface text-sm leading-tight line-clamp-2">{{ tenant.name }}</span>
                  <span class="inline-flex items-center px-2 py-0.5 rounded-full bg-light-surface-container-low text-light-on-surface-variant text-[10px] font-label w-fit">
                    {{ tenant.category || 'Umum' }}
                  </span>
                </div>
              </button>
            </div>
          </main>

          <!-- RIGHT COLUMN: Step 2+3 — Cart & Payment (sticky on desktop) -->
          <aside class="lg:sticky lg:top-16 lg:h-[calc(100vh-64px)] lg:overflow-y-auto bg-light-surface-container-lowest border-t lg:border-t-0 lg:border-l border-light-outline-variant flex flex-col gap-0 pb-24 lg:pb-0">

            <!-- Step 2: Cart -->
            <div class="p-4 lg:p-5 flex flex-col gap-3 border-b border-light-outline-variant">
              <div class="flex items-center justify-between gap-2">
                <div class="flex items-center gap-2">
                  <span class="inline-flex items-center justify-center w-6 h-6 rounded-full bg-light-primary text-light-on-primary text-xs font-bold font-label flex-shrink-0">2</span>
                  <h3 class="font-display font-semibold text-light-on-surface text-sm">Daftar Belanja</h3>
                  <span v-if="cart.length > 0" class="inline-flex items-center justify-center w-5 h-5 rounded-full bg-light-secondary-container text-light-on-secondary-container text-[10px] font-bold">{{ cart.length }}</span>
                </div>
                <button
                  v-if="cart.length > 0"
                  type="button"
                  @click="cart = []"
                  class="text-xs text-light-error hover:underline font-label cursor-pointer"
                >
                  Kosongkan
                </button>
              </div>

              <!-- Cart items -->
              <div v-if="cart.length > 0" class="flex flex-col gap-2 max-h-48 overflow-y-auto">
                <div
                  v-for="(item, idx) in cart"
                  :key="idx"
                  class="flex items-start justify-between gap-3 p-3 rounded-md bg-light-surface-container-low border border-light-outline-variant"
                >
                  <div class="flex-1 min-w-0">
                    <div class="flex items-center gap-1.5 mb-0.5">
                      <span class="font-mono text-[10px] px-1.5 py-0.5 rounded-sm bg-light-primary text-light-on-primary tabular-nums">
                        #{{ tenants.find(t => t.id === item.tenantId)?.booth_number || '?' }}
                      </span>
                    </div>
                    <p class="font-semibold text-light-on-surface text-sm truncate">{{ item.tenantName }}</p>
                    <p v-if="item.itemNote" class="text-xs text-light-on-surface-variant truncate">{{ item.itemNote }}</p>
                  </div>
                  <div class="flex items-center gap-2 flex-shrink-0">
                    <span class="font-mono text-sm tabular-nums text-light-on-surface font-semibold">{{ formatRupiah(item.grossAmount) }}</span>
                    <button
                      @click="removeFromCart(idx)"
                      class="text-light-on-surface-variant hover:text-light-error transition-colors p-1 rounded-md hover:bg-light-error-container cursor-pointer"
                    >
                      <X class="w-4 h-4" />
                    </button>
                  </div>
                </div>
              </div>

              <!-- Empty cart -->
              <div v-else class="flex flex-col items-center justify-center text-center gap-2 p-6 rounded-md bg-light-surface-container-low border border-dashed border-light-outline-variant">
                <ShoppingCart class="w-8 h-8 text-light-on-surface-variant" />
                <p class="text-xs text-light-on-surface-variant">Pilih booth untuk menambah item ke keranjang</p>
              </div>

              <!-- Cart total -->
              <div v-if="cart.length > 0" class="flex items-center justify-between pt-2 border-t border-light-outline-variant">
                <span class="text-sm text-light-on-surface-variant font-label">Total</span>
                <span class="font-mono text-xl font-bold text-light-primary tabular-nums">{{ formatRupiah(cartTotal) }}</span>
              </div>
            </div>

            <!-- Step 3: Payment -->
            <div class="p-4 lg:p-5 flex flex-col gap-4 flex-1">
              <div class="flex items-center gap-2">
                <span class="inline-flex items-center justify-center w-6 h-6 rounded-full bg-light-primary text-light-on-primary text-xs font-bold font-label flex-shrink-0">3</span>
                <h3 class="font-display font-semibold text-light-on-surface text-sm">Pembayaran</h3>
              </div>

              <!-- Payment method toggle -->
              <div class="grid grid-cols-2 gap-1 p-1 rounded-md bg-light-surface-container">
                <button
                  @click="paymentMethod = 'QRIS'"
                  :class="paymentMethod === 'QRIS'
                    ? 'bg-light-surface-container-lowest text-light-primary border border-light-outline-variant shadow-sm'
                    : 'text-light-on-surface-variant hover:bg-light-surface-container-low'"
                  class="flex items-center justify-center gap-2 py-2 rounded-md font-label text-sm font-semibold transition-colors cursor-pointer"
                >
                  <Smartphone class="w-4 h-4" />
                  QRIS
                </button>
                <button
                  @click="paymentMethod = 'CASH'"
                  :class="paymentMethod === 'CASH'
                    ? 'bg-light-surface-container-lowest text-light-primary border border-light-outline-variant shadow-sm'
                    : 'text-light-on-surface-variant hover:bg-light-surface-container-low'"
                  class="flex items-center justify-center gap-2 py-2 rounded-md font-label text-sm font-semibold transition-colors cursor-pointer"
                >
                  <Banknote class="w-4 h-4" />
                  Tunai
                </button>
              </div>

              <!-- QRIS panel -->
              <div v-if="paymentMethod === 'QRIS'" class="flex flex-col items-center text-center gap-3 p-5 rounded-md bg-light-surface-container-low border border-light-outline-variant">
                <Smartphone class="w-10 h-10 text-light-on-surface-variant" />
                <div class="space-y-1">
                  <p class="font-label font-semibold text-light-on-surface text-sm">Bayar via QRIS</p>
                  <p class="text-xs text-light-on-surface-variant">Arahkan kamera ke QR code di mesin kasir atau tunjukkan ke pembeli.</p>
                </div>
              </div>

              <!-- CASH panel -->
              <div v-if="paymentMethod === 'CASH'" class="flex flex-col gap-3">
                <!-- Denomination chips -->
                <div class="grid grid-cols-4 gap-2">
                  <button
                    v-for="chip in [50000, 100000, 200000, 500000]"
                    :key="chip"
                    type="button"
                    @click="addCashTenderedChip(chip)"
                    class="py-1.5 rounded-sm bg-light-surface-container-low border border-light-outline-variant font-mono text-xs tabular-nums text-light-on-surface hover:border-light-primary hover:bg-light-surface-container transition-colors active:scale-95 cursor-pointer touch-manipulation select-none"
                  >
                    +{{ chip >= 1000 ? (chip / 1000) + 'k' : chip }}
                  </button>
                </div>

                <!-- "Uang Pas" chip -->
                <button
                  type="button"
                  @click="setExactCash"
                  class="w-full py-1.5 rounded-sm bg-light-surface-container-low border border-light-outline-variant font-mono text-xs tabular-nums text-light-primary hover:border-light-primary hover:bg-light-primary/5 transition-colors cursor-pointer touch-manipulation select-none"
                >
                  Uang Pas ({{ formatRupiah(cartTotal) }})
                </button>

                <!-- Input uang diterima -->
                <div class="relative">
                  <span class="absolute left-3 top-1/2 -translate-y-1/2 text-sm font-semibold text-light-on-surface-variant">Rp</span>
                  <input
                    type="text"
                    inputmode="numeric"
                    :value="cashTenderedDisplay"
                    @input="handleCashTenderedInput"
                    :placeholder="cartTotal > 0 ? Number(cartTotal).toLocaleString('id-ID') : '0'"
                    class="w-full bg-light-surface-container-lowest border border-light-outline-variant focus:border-light-primary rounded-md pl-10 pr-9 py-2.5 text-base font-mono font-bold text-light-on-surface tabular-nums placeholder-light-on-surface-variant focus:outline-none focus:ring-2 focus:ring-light-primary/20 transition-colors"
                  />
                  <button
                    v-if="cashTendered"
                    @click="cashTendered = null; cashTenderedDisplay = ''"
                    type="button"
                    class="absolute right-3 top-1/2 -translate-y-1/2 text-light-on-surface-variant hover:text-light-on-surface cursor-pointer"
                  >
                    <X class="w-4 h-4" />
                  </button>
                </div>

                <!-- Change box -->
                <div
                  :class="isCashInsufficient
                    ? 'bg-light-error-container border-light-error'
                    : 'bg-light-secondary-container border-light-primary'"
                  class="flex items-center justify-between gap-3 p-3 rounded-md border"
                >
                  <span class="text-xs font-label font-semibold text-light-on-surface">Kembalian</span>
                  <div v-if="isCashInsufficient" class="flex items-center gap-1.5 text-light-error font-semibold text-sm animate-pulse">
                    <AlertCircle class="w-4 h-4" />
                    <span class="font-mono tabular-nums">Kurang {{ formatRupiah(cashShortage) }}</span>
                  </div>
                  <span v-else class="font-mono text-lg font-bold text-light-primary tabular-nums">
                    {{ formatRupiah(cashChange) }}
                  </span>
                </div>
              </div>

              <!-- Receipt badge -->
              <div class="flex items-center gap-2">
                <span class="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-light-surface-container-low border border-light-outline-variant font-mono text-xs tabular-nums text-light-on-surface-variant">
                  <Receipt class="w-3.5 h-3.5" />
                  Nomor Struk: AUTO (#)
                </span>
              </div>

              <!-- CTA: Process payment -->
              <button
                @click="processPayment"
                :disabled="cart.length === 0 || processingPayment || !selectedEventId || isCashInsufficient"
                class="w-full inline-flex items-center justify-center gap-2 px-5 py-3.5 rounded-md bg-light-primary text-light-on-primary font-label font-semibold text-base hover:opacity-90 active:scale-[0.99] disabled:opacity-40 disabled:cursor-not-allowed transition-all duration-150 cursor-pointer shadow-sm shadow-light-primary/20"
              >
                <Loader2 v-if="processingPayment" class="w-5 h-5 animate-spin" />
                <CreditCard v-else class="w-5 h-5" />
                {{ processingPayment ? 'Memproses…' : 'Proses Pembayaran' }}
              </button>
            </div>
          </aside>
        </div>
      </template>
    </div>

    <!-- Recent Transactions Drawer (bottom, full-width) -->
    <div class="fixed bottom-0 left-0 right-0 z-40" style="padding-bottom: env(safe-area-inset-bottom, 0px);">
      <!-- Toggle Button -->
      <button
        @click="drawerOpen = !drawerOpen"
        class="hidden lg:flex w-full bg-light-surface-container-lowest border-t border-light-outline-variant px-5 py-3 items-center justify-between hover:bg-light-surface-container-low transition-colors cursor-pointer"
      >
        <div class="flex items-center gap-2">
          <Clock class="w-4 h-4 text-light-on-surface-variant" />
          <span class="text-sm font-label font-semibold text-light-on-surface">Transaksi Terbaru</span>
          <span v-if="recentTransactions.length > 0" class="bg-light-secondary-container text-light-on-secondary-container text-xs font-semibold rounded-full px-2 py-0.5">
            <span v-if="txSearchQuery || txStatusFilter !== 'ALL'">
              {{ filteredRecentTransactions.length }} / {{ recentTransactions.length }}
            </span>
            <span v-else>{{ recentTransactions.length }}</span>
          </span>
        </div>
        <ChevronUp :class="['w-4 h-4 text-light-on-surface-variant transition-transform duration-200', drawerOpen ? 'rotate-180' : '']" />
      </button>

      <!-- Drawer Content -->
      <Transition name="drawer">
        <div v-if="drawerOpen" class="bg-light-surface-container-lowest border-t border-light-outline-variant max-h-[32rem] flex flex-col">
          <!-- Filter Bar -->
          <div
            v-if="selectedEventId && recentTransactions.length > 0"
            class="p-3 border-b border-light-outline-variant sticky top-0 z-10 bg-light-surface-container-lowest"
          >
            <div class="flex items-center gap-2 flex-wrap sm:flex-nowrap">
              <!-- Search -->
              <div class="relative flex-1 min-w-[180px]">
                <Search class="w-3.5 h-3.5 absolute left-3 top-1/2 -translate-y-1/2 text-light-on-surface-variant pointer-events-none" />
                <input
                  v-model="txSearchQuery"
                  type="text"
                  placeholder="Cari kode struk atau nama tenant..."
                  class="w-full bg-light-surface-container-low border border-light-outline-variant focus:border-light-primary text-light-on-surface placeholder-light-on-surface-variant rounded-md pl-8 pr-8 py-1.5 text-xs focus:outline-none focus:ring-2 focus:ring-light-primary/20 transition-all"
                />
                <button
                  v-if="txSearchQuery"
                  type="button"
                  @click="txSearchQuery = ''"
                  class="absolute right-2 top-1/2 -translate-y-1/2 p-0.5 text-light-on-surface-variant hover:text-light-on-surface rounded-md cursor-pointer"
                >
                  <X class="w-3.5 h-3.5" />
                </button>
              </div>
              <!-- Status filter pills -->
              <div class="flex items-center gap-1 shrink-0">
                <button
                  type="button"
                  @click="txStatusFilter = 'ALL'"
                  :class="txStatusFilter === 'ALL'
                    ? 'bg-light-surface-container text-light-on-surface font-bold border-light-outline'
                    : 'bg-light-surface-container-low hover:bg-light-surface-container text-light-on-surface-variant border-light-outline-variant'"
                  class="px-2.5 py-1 rounded-md text-[11px] border font-label font-medium transition-colors cursor-pointer"
                >Semua</button>
                <button
                  type="button"
                  @click="txStatusFilter = 'COMPLETED'"
                  :class="txStatusFilter === 'COMPLETED'
                    ? 'bg-light-secondary-container text-light-on-secondary-container font-bold border-light-secondary'
                    : 'bg-light-surface-container-low hover:bg-light-surface-container text-light-on-surface-variant border-light-outline-variant'"
                  class="px-2.5 py-1 rounded-md text-[11px] border font-label font-medium transition-colors cursor-pointer"
                >Completed</button>
                <button
                  type="button"
                  @click="txStatusFilter = 'VOID'"
                  :class="txStatusFilter === 'VOID'
                    ? 'bg-light-error-container text-light-error font-bold border-light-error'
                    : 'bg-light-surface-container-low hover:bg-light-surface-container text-light-on-surface-variant border-light-outline-variant'"
                  class="px-2.5 py-1 rounded-md text-[11px] border font-label font-medium transition-colors cursor-pointer"
                >Void</button>
              </div>
            </div>
          </div>

          <!-- Transaction list -->
          <div class="overflow-y-auto flex-1 divide-y divide-light-outline-variant">
            <div v-if="loadingTransactions" class="p-6 text-center text-light-on-surface-variant text-sm">
              <Loader2 class="w-5 h-5 animate-spin mx-auto mb-2" />
              Memuat transaksi…
            </div>
            <div v-else-if="!selectedEventId" class="p-6 text-center text-light-on-surface-variant text-sm">
              Pilih event untuk melihat transaksi.
            </div>
            <div v-else-if="recentTransactions.length === 0" class="p-6 text-center text-light-on-surface-variant text-sm">
              Belum ada transaksi.
            </div>
            <div
              v-else-if="filteredRecentTransactions.length === 0"
              class="p-8 text-center text-light-on-surface-variant text-xs space-y-2"
            >
              <Search class="w-6 h-6 text-light-on-surface-variant mx-auto" />
              <p class="font-label font-medium text-light-on-surface">Tidak ada transaksi yang cocok.</p>
              <button
                type="button"
                @click="txSearchQuery = ''; txStatusFilter = 'ALL'"
                class="inline-flex items-center gap-1 text-light-primary hover:underline cursor-pointer text-xs"
              >
                <RefreshCw class="w-3 h-3" />
                <span>Reset filter</span>
              </button>
            </div>
            <div
              v-else
              v-for="tx in filteredRecentTransactions"
              :key="tx.id"
              class="px-4 py-3 flex items-start gap-3 hover:bg-light-surface-container-low transition-colors"
            >
              <div class="flex-1 min-w-0 space-y-2">
                <div class="flex items-center gap-2 flex-wrap">
                  <button
                    @click="openReceiptModalFromRecent(tx)"
                    class="inline-flex items-center gap-1 font-mono text-sm font-bold text-light-primary hover:underline cursor-pointer tabular-nums"
                    title="Lihat Struk Digital"
                  >
                    <Receipt class="w-3.5 h-3.5" />
                    {{ tx.receipt_code }}
                  </button>
                  <span :class="[
                    'text-xs font-label font-semibold rounded-full px-2 py-0.5',
                    tx.payment_method === 'QRIS'
                      ? 'bg-light-surface-container text-light-on-surface-variant'
                      : 'bg-light-secondary-container text-light-on-secondary-container'
                  ]">{{ tx.payment_method }}</span>
                  <span :class="[
                    'text-xs font-label font-semibold rounded-full px-2 py-0.5',
                    tx.status === 'COMPLETED'
                      ? 'bg-light-secondary-container text-light-on-secondary-container'
                      : 'bg-light-error-container text-light-error'
                  ]">{{ tx.status }}</span>
                  <span v-if="tx.void_reason" class="text-[11px] text-light-error italic">({{ tx.void_reason }})</span>
                </div>
                <div class="flex items-center gap-2 text-xs flex-wrap">
                  <span class="font-mono font-bold text-light-primary tabular-nums">{{ formatRupiah(tx.total_amount) }}</span>
                  <span class="text-light-on-surface-variant">•</span>
                  <span class="text-light-on-surface-variant">{{ formatDate(tx.created_at) }}</span>
                  <span v-if="tx.payment_method === 'CASH' && tx.cash_tendered" class="text-light-on-surface-variant font-mono text-[11px] tabular-nums">
                    • Tunai: {{ formatRupiah(tx.cash_tendered) }} (Kembali: {{ formatRupiah(tx.change_amount || 0) }})
                  </span>
                  <span v-if="tx.transaction_items?.length" class="text-light-on-surface-variant">
                    • {{ tx.transaction_items.length }} item{{ tx.transaction_items.length > 1 ? 's' : '' }}
                  </span>
                </div>
                <!-- Item breakdown -->
                <div
                  v-if="tx.transaction_items && tx.transaction_items.length > 0"
                  class="bg-light-surface-container-low border border-light-outline-variant rounded-md p-2.5 space-y-1.5"
                >
                  <div
                    v-for="item in tx.transaction_items"
                    :key="item.id"
                    class="flex items-start justify-between gap-2 text-xs"
                  >
                    <div class="flex-1 min-w-0">
                      <span class="font-label font-medium text-light-on-surface">
                        {{ item.tenants?.name || 'Tenant' }}
                        <span v-if="item.tenants?.booth_number" class="text-light-on-surface-variant font-mono text-[11px] tabular-nums">
                          ({{ item.tenants.booth_number }})
                        </span>
                      </span>
                      <p v-if="item.item_note" class="text-[11px] text-light-on-surface-variant italic truncate">{{ item.item_note }}</p>
                    </div>
                    <span class="font-mono font-medium text-light-on-surface shrink-0 tabular-nums">
                      {{ formatRupiah(item.gross_amount) }}
                    </span>
                  </div>
                </div>
              </div>
              <button
                v-if="tx.status === 'COMPLETED'"
                @click="openVoidModal(tx)"
                class="flex-shrink-0 text-xs font-label font-semibold text-light-error border border-light-error/30 hover:bg-light-error-container rounded-md px-2.5 py-1 transition-colors cursor-pointer mt-0.5"
              >
                VOID
              </button>
            </div>
          </div>
        </div>
      </Transition>
    </div>

    <!-- Add to Cart Modal -->
    <Transition name="modal">
      <div v-if="addToCartModal.open" class="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" @click="closeAddToCart" />
        <div class="relative bg-light-surface-container-lowest border border-light-outline-variant rounded-xl w-full max-w-sm shadow-2xl z-10">
          <!-- Modal Header -->
          <div class="flex items-center justify-between px-5 pt-5 pb-3 border-b border-light-outline-variant">
            <div>
              <p class="text-xs text-light-on-surface-variant uppercase tracking-widest font-label font-semibold">Tambah ke Keranjang</p>
              <h3 class="font-display font-bold text-light-on-surface mt-0.5">{{ addToCartModal.tenant?.name }}</h3>
            </div>
            <button @click="closeAddToCart" class="text-light-on-surface-variant hover:text-light-on-surface p-1 rounded-md hover:bg-light-surface-container-low transition-colors">
              <X class="w-5 h-5" />
            </button>
          </div>

          <!-- Modal Body -->
          <div class="p-5 flex flex-col gap-4">
            <!-- Booth info -->
            <div class="flex items-center justify-between text-xs flex-wrap gap-2">
              <div class="flex items-center gap-2">
                <span class="bg-light-surface-container rounded-md px-2 py-0.5 font-mono text-light-primary font-semibold tabular-nums">
                  #{{ addToCartModal.tenant?.booth_number || '?' }}
                </span>
                <span class="text-light-on-surface-variant font-label">{{ addToCartModal.tenant?.category || 'Umum' }}</span>
              </div>
              <div class="text-[11px] font-label bg-light-surface-container-low rounded-md px-2 py-1 border border-light-outline-variant">
                Split: <span class="text-light-tertiary font-semibold">Venue {{ addToCartModal.tenant?.venue_share_percent ?? 10 }}%</span>
                <span class="text-light-on-surface-variant mx-1">•</span>
                <span class="text-light-warning font-semibold">EO {{ addToCartModal.tenant?.organizer_share_percent ?? 0 }}%</span>
                <span class="text-light-on-surface-variant mx-1">•</span>
                <span class="text-light-primary font-semibold">Tenant {{ Math.max(0, 100 - (Number(addToCartModal.tenant?.venue_share_percent ?? 10) + Number(addToCartModal.tenant?.organizer_share_percent ?? 0))) }}%</span>
              </div>
            </div>

            <!-- Amount Input -->
            <div>
              <label class="text-xs text-light-on-surface-variant uppercase tracking-widest font-label font-semibold mb-2 block">Jumlah (Rp)</label>
              <div class="relative">
                <span class="absolute left-3.5 top-1/2 -translate-y-1/2 text-light-on-surface-variant font-semibold text-lg pointer-events-none">Rp</span>
                <input
                  :value="addToCartModal.displayAmount"
                  @input="handleAmountInput"
                  type="text"
                  inputmode="numeric"
                  placeholder="0"
                  class="w-full bg-light-surface-container-low border border-light-outline-variant focus:border-light-primary rounded-md pl-12 pr-4 py-3 text-2xl font-mono font-bold text-light-on-surface tabular-nums placeholder-light-on-surface-variant focus:outline-none focus:ring-2 focus:ring-light-primary/20 transition-colors"
                />
              </div>

              <!-- Quick Add Chips -->
              <div class="flex items-center gap-1.5 flex-wrap mt-2.5">
                <button type="button" @click="addQuickAmount(10000)"
                  class="px-2.5 py-1 text-xs font-mono font-semibold rounded-md bg-light-surface-container-low border border-light-outline-variant hover:border-light-primary text-light-on-surface transition-colors active:scale-95 cursor-pointer touch-manipulation select-none tabular-nums">
                  +10.000
                </button>
                <button type="button" @click="addQuickAmount(25000)"
                  class="px-2.5 py-1 text-xs font-mono font-semibold rounded-md bg-light-surface-container-low border border-light-outline-variant hover:border-light-primary text-light-on-surface transition-colors active:scale-95 cursor-pointer touch-manipulation select-none tabular-nums">
                  +25.000
                </button>
                <button type="button" @click="addQuickAmount(50000)"
                  class="px-2.5 py-1 text-xs font-mono font-semibold rounded-md bg-light-surface-container-low border border-light-outline-variant hover:border-light-primary text-light-on-surface transition-colors active:scale-95 cursor-pointer touch-manipulation select-none tabular-nums">
                  +50.000
                </button>
                <button type="button" @click="addQuickAmount(100000)"
                  class="px-2.5 py-1 text-xs font-mono font-semibold rounded-md bg-light-surface-container-low border border-light-outline-variant hover:border-light-primary text-light-on-surface transition-colors active:scale-95 cursor-pointer touch-manipulation select-none tabular-nums">
                  +100.000
                </button>
                <button type="button" @click="clearAmount"
                  class="px-2.5 py-1 text-xs font-label font-semibold rounded-md bg-light-error-container text-light-error border border-light-error/30 hover:opacity-80 transition-colors active:scale-95 ml-auto cursor-pointer touch-manipulation select-none">
                  Clear
                </button>
              </div>
            </div>

            <!-- Note Input -->
            <div>
              <label class="text-xs text-light-on-surface-variant uppercase tracking-widest font-label font-semibold mb-2 block">Catatan (Opsional)</label>
              <input
                v-model="addToCartModal.note"
                type="text"
                placeholder="e.g. Nasi Goreng x2"
                class="w-full bg-light-surface-container-low border border-light-outline-variant focus:border-light-primary rounded-md px-4 py-2.5 text-sm text-light-on-surface placeholder-light-on-surface-variant focus:outline-none focus:ring-2 focus:ring-light-primary/20 transition-colors"
              />
            </div>

            <!-- Add Button -->
            <button
              @click="addToCart"
              :disabled="!addToCartModal.amount || addToCartModal.amount <= 0"
              class="w-full py-3.5 rounded-md font-label font-semibold text-sm bg-light-primary text-light-on-primary transition-all duration-150 disabled:opacity-40 disabled:cursor-not-allowed active:scale-[0.98] flex items-center justify-center gap-2 hover:opacity-90"
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
        <div class="relative bg-light-surface-container-lowest border border-light-outline-variant rounded-xl w-full max-w-sm shadow-2xl z-10">
          <div class="flex items-center justify-between px-5 pt-5 pb-3 border-b border-light-outline-variant">
            <div class="flex items-center gap-2 text-light-error">
              <AlertTriangle class="w-5 h-5 flex-shrink-0" />
              <div>
                <p class="text-xs text-light-on-surface-variant uppercase tracking-widest font-label font-semibold">Otorisasi Void Transaksi</p>
                <h3 class="font-display font-bold text-light-on-surface mt-0.5">{{ voidModal.transaction?.receipt_code }}</h3>
              </div>
            </div>
            <button @click="closeVoidModal" class="text-light-on-surface-variant hover:text-light-on-surface p-1 rounded-md hover:bg-light-surface-container-low transition-colors">
              <X class="w-5 h-5" />
            </button>
          </div>
          <div class="p-5 flex flex-col gap-4">
            <p class="text-xs text-light-on-surface-variant">
              Transaksi sebesar <strong class="text-light-error font-mono tabular-nums">{{ formatRupiah(voidModal.transaction?.total_amount) }}</strong> akan di-void. Membutuhkan verifikasi supervisor.
            </p>

            <!-- Supervisor PIN -->
            <div>
              <label class="text-xs text-light-on-surface-variant uppercase tracking-wider font-label font-semibold mb-1.5 flex items-center gap-1.5">
                <Lock class="w-3.5 h-3.5 text-light-warning" />
                <span>PIN Supervisor / Admin</span>
                <span class="text-light-error">*</span>
              </label>
              <input
                v-model="voidModal.pin"
                type="password"
                maxlength="6"
                inputmode="numeric"
                placeholder="Masukkan 6-digit PIN"
                class="w-full bg-light-surface-container-low border border-light-outline-variant focus:border-light-error rounded-md px-4 py-2.5 text-center text-lg font-mono tracking-widest text-light-on-surface placeholder-light-on-surface-variant focus:outline-none focus:ring-2 focus:ring-light-error/20 transition-colors"
                @keydown.enter="confirmVoid"
              />
              <p v-if="voidModal.pinError" class="text-xs text-light-error mt-1 flex items-center gap-1">
                <AlertCircle class="w-3 h-3" />
                {{ voidModal.pinError }}
              </p>

              <!-- Touch-friendly 3x4 Keypad -->
              <div class="grid grid-cols-3 gap-1.5 w-full max-w-[220px] mx-auto pt-2">
                <button
                  v-for="n in [1, 2, 3, 4, 5, 6, 7, 8, 9]"
                  :key="n"
                  type="button"
                  @click="appendVoidPinDigit(String(n))"
                  class="h-10 rounded-md bg-light-surface-container-low hover:bg-light-surface-container active:scale-95 border border-light-outline-variant text-base font-bold font-mono text-light-on-surface flex items-center justify-center transition-all cursor-pointer touch-manipulation select-none"
                >
                  {{ n }}
                </button>
                <button
                  type="button"
                  @click="clearVoidPin"
                  class="h-10 rounded-md bg-light-surface-container-low hover:bg-light-surface-container active:scale-95 border border-light-outline-variant text-[11px] font-label font-bold text-light-on-surface-variant hover:text-light-on-surface flex items-center justify-center transition-all uppercase tracking-wider cursor-pointer touch-manipulation select-none"
                >
                  Clear
                </button>
                <button
                  type="button"
                  @click="appendVoidPinDigit('0')"
                  class="h-10 rounded-md bg-light-surface-container-low hover:bg-light-surface-container active:scale-95 border border-light-outline-variant text-base font-bold font-mono text-light-on-surface flex items-center justify-center transition-all cursor-pointer touch-manipulation select-none"
                >
                  0
                </button>
                <button
                  type="button"
                  @click="deleteVoidPinDigit"
                  class="h-10 rounded-md bg-light-surface-container-low hover:bg-light-surface-container active:scale-95 border border-light-outline-variant text-light-on-surface-variant hover:text-light-on-surface flex items-center justify-center transition-all cursor-pointer touch-manipulation select-none"
                  title="Hapus"
                >
                  <Delete class="w-4 h-4" />
                </button>
              </div>
            </div>

            <!-- Void Reason -->
            <div>
              <label class="text-xs text-light-on-surface-variant uppercase tracking-wider font-label font-semibold mb-1.5 block">
                Alasan Void <span class="text-light-error">*</span>
              </label>
              <textarea
                v-model="voidModal.reason"
                placeholder="Contoh: Salah nominal, pembeli membatalkan pesanan…"
                rows="2"
                class="w-full bg-light-surface-container-low border border-light-outline-variant focus:border-light-error rounded-md px-3.5 py-2 text-xs text-light-on-surface placeholder-light-on-surface-variant focus:outline-none focus:ring-2 focus:ring-light-error/20 transition-colors resize-none"
              />
            </div>

            <div class="flex gap-2 pt-1">
              <button
                type="button"
                @click="closeVoidModal"
                class="flex-1 py-2.5 rounded-md font-label font-semibold text-xs bg-light-surface-container-low text-light-on-surface border border-light-outline-variant hover:bg-light-surface-container transition-colors"
              >
                Batal
              </button>
              <button
                type="button"
                @click="confirmVoid"
                :disabled="!voidModal.reason.trim() || !voidModal.pin || voidModal.pin.length < 6 || voidModal.processing"
                class="flex-1 py-2.5 rounded-md font-label font-semibold text-xs bg-light-error text-light-on-error hover:opacity-90 transition-all duration-150 disabled:opacity-40 disabled:cursor-not-allowed flex items-center justify-center gap-2 cursor-pointer"
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
        <div class="relative bg-light-surface-container-lowest border border-light-outline-variant rounded-xl w-full max-w-md shadow-2xl z-10 overflow-hidden">
          <!-- Modal Header -->
          <div class="flex items-center justify-between px-5 py-3.5 border-b border-light-outline-variant bg-light-surface-container-low">
            <div class="flex items-center gap-2">
              <div class="w-7 h-7 rounded-md bg-light-secondary-container border border-light-outline-variant flex items-center justify-center text-light-primary">
                <Receipt class="w-4 h-4" />
              </div>
              <div>
                <h3 class="font-display font-bold text-light-on-surface text-sm">Struk Digital</h3>
                <p class="text-[11px] text-light-on-surface-variant">Bukti Pembayaran Transaksi</p>
              </div>
            </div>
            <button
              @click="receiptModal.open = false"
              class="text-light-on-surface-variant hover:text-light-on-surface p-1 rounded-md hover:bg-light-surface-container transition-colors"
            >
              <X class="w-5 h-5" />
            </button>
          </div>

          <!-- Receipt Paper -->
          <div class="p-5 space-y-4 max-h-[75vh] overflow-y-auto">
            <div class="bg-light-surface-container-low border border-light-outline-variant rounded-md p-4 font-mono text-xs text-light-on-surface space-y-3">
              <!-- Header -->
              <div class="text-center pb-3 border-b border-dashed border-light-outline-variant space-y-1">
                <h4 class="font-display font-black text-sm tracking-widest text-light-on-surface uppercase">Nyaris Pop-Up POS</h4>
                <p v-if="receiptModal.transaction?.event_name" class="text-light-on-surface-variant font-label text-xs">
                  {{ receiptModal.transaction.event_name }}
                </p>
                <p class="text-light-primary text-xs font-bold pt-1 tabular-nums">
                  #{{ receiptModal.transaction?.receipt_code }}
                </p>
                <div class="text-[11px] text-light-on-surface-variant pt-0.5">
                  {{ formatDate(receiptModal.transaction?.created_at) }}
                </div>
                <div class="inline-block mt-1">
                  <span :class="[
                    'text-[10px] font-label font-bold px-2 py-0.5 rounded-full uppercase tracking-wider border',
                    receiptModal.transaction?.payment_method === 'QRIS'
                      ? 'bg-light-surface-container text-light-on-surface-variant border-light-outline-variant'
                      : 'bg-light-secondary-container text-light-on-secondary-container border-light-secondary-container'
                  ]">
                    {{ receiptModal.transaction?.payment_method }}
                  </span>
                </div>
              </div>

              <!-- Items -->
              <div class="space-y-2 py-1">
                <div
                  v-for="(item, idx) in receiptModal.items"
                  :key="idx"
                  class="flex justify-between items-start gap-2"
                >
                  <div class="min-w-0 flex-1">
                    <div class="text-light-on-surface font-semibold truncate">
                      {{ item.tenantName }}
                      <span v-if="item.boothNumber" class="text-light-on-surface-variant text-[10px] tabular-nums">({{ item.boothNumber }})</span>
                    </div>
                    <div v-if="item.itemNote" class="text-[10px] text-light-on-surface-variant italic truncate">{{ item.itemNote }}</div>
                  </div>
                  <div class="font-bold text-light-on-surface shrink-0 tabular-nums">
                    {{ formatRupiah(item.grossAmount) }}
                  </div>
                </div>
              </div>

              <!-- Totals -->
              <div class="pt-3 border-t border-dashed border-light-outline-variant space-y-1.5">
                <div class="flex justify-between text-sm font-bold text-light-on-surface">
                  <span>TOTAL</span>
                  <span class="text-light-primary tabular-nums">{{ formatRupiah(receiptModal.transaction?.total_amount) }}</span>
                </div>
                <template v-if="receiptModal.transaction?.payment_method === 'CASH'">
                  <div class="flex justify-between text-light-on-surface-variant text-xs pt-1">
                    <span>Uang Diterima</span>
                    <span class="tabular-nums">{{ formatRupiah(receiptModal.transaction?.cash_tendered || receiptModal.transaction?.total_amount) }}</span>
                  </div>
                  <div class="flex justify-between text-xs font-semibold text-light-primary">
                    <span>Kembalian</span>
                    <span class="tabular-nums">{{ formatRupiah(receiptModal.transaction?.change_amount || 0) }}</span>
                  </div>
                </template>
              </div>

              <!-- Footer -->
              <div class="text-center pt-3 border-t border-dashed border-light-outline-variant text-[10px] text-light-on-surface-variant">
                Terima kasih telah berbelanja!
              </div>
            </div>

            <!-- Action Buttons -->
            <div class="flex gap-2.5">
              <button
                type="button"
                @click="copyReceiptText"
                class="flex-1 py-2.5 rounded-md font-label font-semibold text-xs transition-all duration-150 flex items-center justify-center gap-1.5 bg-light-surface-container-low border border-light-outline-variant text-light-on-surface hover:bg-light-surface-container active:scale-95 cursor-pointer"
              >
                <Check v-if="receiptModal.copied" class="w-4 h-4 text-light-primary" />
                <Copy v-else class="w-4 h-4" />
                {{ receiptModal.copied ? 'Disalin!' : 'Copy Text' }}
              </button>
              <button
                type="button"
                @click="receiptModal.open = false"
                class="px-5 py-2.5 rounded-md font-label font-semibold text-xs bg-light-primary text-light-on-primary hover:opacity-90 transition-all duration-150 active:scale-95 cursor-pointer"
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
import { ref, computed, watch, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import {
  ShoppingCart, CalendarDays, Hash, X, Plus, CreditCard, Clock,
  ChevronUp, AlertCircle, CheckCircle, Loader2, RefreshCw,
  Smartphone, Banknote, AlertTriangle, XCircle, ShieldCheck,
  Receipt, Copy, Check, LogOut, Lock, Search, Delete
} from 'lucide-vue-next'
import { supabase } from '@/lib/supabase.js'
import { useAuth } from '@/lib/useAuth.js'
import { useEvents } from '@/lib/useEvents.js'
import { formatRupiah } from '@/lib/currency.js'

const router = useRouter()
const { signOut } = useAuth()
const { selectedEventId: globalEventId, selectEventId: setGlobalEventId } = useEvents()

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

watch(globalEventId, async (newId) => {
  if (newId && newId !== selectedEventId.value && events.value.some((e) => e.id === newId)) {
    selectedEventId.value = newId
    await onEventChange()
  }
})

// ─── Tenant Search & Category Filtering ───────────────────────────────────────

const tenantSearchQuery = ref('')
const selectedTenantCategory = ref('ALL')

const availableTenantCategories = computed(() => {
  const set = new Set()
  for (const t of tenants.value) {
    const cat = (t.category || '').trim()
    if (cat) set.add(cat)
  }
  const sorted = Array.from(set).sort((a, b) => a.localeCompare(b, 'id', { sensitivity: 'base' }))
  return ['ALL', ...sorted]
})

const filteredTenants = computed(() => {
  const q = tenantSearchQuery.value.trim().toLowerCase()
  const cat = selectedTenantCategory.value

  return tenants.value.filter((t) => {
    // 1. Category match
    if (cat !== 'ALL' && (t.category || '').trim() !== cat) {
      return false
    }
    // 2. Search query match against brand name, booth number, or category
    if (q) {
      const name = (t.name || '').toLowerCase()
      const booth = (t.booth_number || '').toLowerCase()
      const category = (t.category || '').toLowerCase()
      if (!name.includes(q) && !booth.includes(q) && !category.includes(q)) {
        return false
      }
    }
    return true
  })
})

watch(selectedEventId, () => {
  tenantSearchQuery.value = ''
  selectedTenantCategory.value = 'ALL'
  txSearchQuery.value = ''
  txStatusFilter.value = 'ALL'
})

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

// ─── Recent Transactions Search & Status Filtering ───────────────────────────

const txSearchQuery = ref('')
const txStatusFilter = ref('ALL') // 'ALL' | 'COMPLETED' | 'VOID'

const filteredRecentTransactions = computed(() => {
  const q = txSearchQuery.value.trim().toLowerCase()
  const status = txStatusFilter.value

  return recentTransactions.value.filter((tx) => {
    // 1. Status Filter
    if (status === 'COMPLETED' && tx.status !== 'COMPLETED') {
      return false
    }
    if (status === 'VOID' && tx.status !== 'VOID' && tx.status !== 'VOIDED') {
      return false
    }

    // 2. Search Query (receipt code, void reason, or tenant name / item notes in transaction)
    if (q) {
      const code = (tx.receipt_code || '').toLowerCase()
      const voidReason = (tx.void_reason || '').toLowerCase()
      let matches = code.includes(q) || voidReason.includes(q)

      if (!matches && tx.transaction_items && tx.transaction_items.length > 0) {
        matches = tx.transaction_items.some((item) => {
          const tName = (item.tenants?.name || '').toLowerCase()
          const note = (item.item_note || '').toLowerCase()
          return tName.includes(q) || note.includes(q)
        })
      }

      if (!matches) return false
    }

    return true
  })
})

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

function appendVoidPinDigit(digit) {
  if ((voidModal.value.pin || '').length < 6) {
    voidModal.value.pin = (voidModal.value.pin || '') + digit
    voidModal.value.pinError = ''
  }
}

function clearVoidPin() {
  voidModal.value.pin = ''
  voidModal.value.pinError = ''
}

function deleteVoidPinDigit() {
  voidModal.value.pin = (voidModal.value.pin || '').slice(0, -1)
  voidModal.value.pinError = ''
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
      .select('id, name, venue, event_dates, status, is_active, created_at')
      .order('created_at', { ascending: false })
    if (error) throw error
    // Filter to only ACTIVE events
    events.value = (data || []).filter((e) => (e.status ? e.status === 'ACTIVE' : e.is_active !== false))

    // Auto-select the first active event or maintain current if still active
    const globalMatch = globalEventId.value && events.value.find((e) => e.id === globalEventId.value)
    const stillActive = events.value.some((e) => e.id === selectedEventId.value)
    if (globalMatch) {
      selectedEventId.value = globalMatch.id
      await onEventChange()
    } else if ((!selectedEventId.value || !stillActive) && events.value.length > 0) {
      selectedEventId.value = events.value[0].id
      await onEventChange()
    } else if (events.value.length === 0) {
      selectedEventId.value = ''
      tenants.value = []
      cart.value = []
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
  if (selectedEventId.value && selectedEventId.value !== globalEventId.value) {
    setGlobalEventId(selectedEventId.value)
  }
  cart.value = []
  receiptCode.value = 'AUTO'
  tenantSearchQuery.value = ''
  selectedTenantCategory.value = 'ALL'
  txSearchQuery.value = ''
  txStatusFilter.value = 'ALL'
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
  max-height: 560px;
}

/* Hide scrollbar utility */
.no-scrollbar {
  -ms-overflow-style: none;
  scrollbar-width: none;
}
.no-scrollbar::-webkit-scrollbar {
  display: none;
}
</style>

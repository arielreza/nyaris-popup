<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue'
import { Calendar as CalendarIcon, ChevronLeft, ChevronRight, Check } from 'lucide-vue-next'

const props = defineProps({
  start: {
    type: String,
    default: () => new Date().toISOString().slice(0, 10),
  },
  end: {
    type: String,
    default: () => new Date().toISOString().slice(0, 10),
  },
})

const emit = defineEmits(['update:start', 'update:end'])

const MONTH_NAMES = [
  'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
  'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
]
const SHORT_MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des']
const DAY_HEADERS = ['Min', 'Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab']

const pickerRef = ref(null)
const isOpen = ref(false)

// View month & year
const initialDate = props.start ? new Date(props.start + 'T00:00:00') : new Date()
const viewYear = ref(initialDate.getFullYear())
const viewMonth = ref(initialDate.getMonth())

// Selection state
const isSelectingEnd = ref(false)
const hoverDate = ref(null)

// Sync view when props change externally and picker is closed
watch(
  () => props.start,
  (newStart) => {
    if (newStart && !isOpen.value) {
      const d = new Date(newStart + 'T00:00:00')
      viewYear.value = d.getFullYear()
      viewMonth.value = d.getMonth()
    }
  }
)

function togglePicker() {
  if (!isOpen.value) {
    if (props.start) {
      const d = new Date(props.start + 'T00:00:00')
      viewYear.value = d.getFullYear()
      viewMonth.value = d.getMonth()
    }
    isSelectingEnd.value = false
    hoverDate.value = null
  }
  isOpen.value = !isOpen.value
}

function closePicker() {
  isOpen.value = false
  isSelectingEnd.value = false
  hoverDate.value = null
}

// ── Navigation ───────────────────────────────────────────────────────────────

function prevMonth() {
  if (viewYear.value === 2024 && viewMonth.value === 0) return
  if (viewMonth.value === 0) {
    viewMonth.value = 11
    viewYear.value--
  } else {
    viewMonth.value--
  }
}

function nextMonth() {
  if (viewYear.value === 2035 && viewMonth.value === 11) return
  if (viewMonth.value === 11) {
    viewMonth.value = 0
    viewYear.value++
  } else {
    viewMonth.value++
  }
}

const currentMonthYearLabel = computed(() => {
  return `${MONTH_NAMES[viewMonth.value]} ${viewYear.value}`
})

// ── Calendar Days Calculation ────────────────────────────────────────────────

const calendarDays = computed(() => {
  const year = viewYear.value
  const month = viewMonth.value

  const firstDayOfWeek = new Date(year, month, 1).getDay()
  const daysInMonth = new Date(year, month + 1, 0).getDate()
  const daysInPrevMonth = new Date(year, month, 0).getDate()

  const todayStr = new Date().toISOString().slice(0, 10)
  const days = []

  // Previous month trailing days
  for (let i = firstDayOfWeek - 1; i >= 0; i--) {
    const day = daysInPrevMonth - i
    const prevM = month === 0 ? 11 : month - 1
    const prevY = month === 0 ? year - 1 : year
    const dateStr = `${prevY}-${String(prevM + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`
    days.push({
      dateStr,
      dayNum: day,
      isCurrentMonth: false,
      isToday: dateStr === todayStr,
    })
  }

  // Current month days
  for (let d = 1; d <= daysInMonth; d++) {
    const dateStr = `${year}-${String(month + 1).padStart(2, '0')}-${String(d).padStart(2, '0')}`
    days.push({
      dateStr,
      dayNum: d,
      isCurrentMonth: true,
      isToday: dateStr === todayStr,
    })
  }

  // Next month leading days to complete grid (up to 35 or 42 cells)
  const remaining = (7 - (days.length % 7)) % 7
  for (let d = 1; d <= remaining; d++) {
    const nextM = month === 11 ? 0 : month + 1
    const nextY = month === 11 ? year + 1 : year
    const dateStr = `${nextY}-${String(nextM + 1).padStart(2, '0')}-${String(d).padStart(2, '0')}`
    days.push({
      dateStr,
      dayNum: d,
      isCurrentMonth: false,
      isToday: dateStr === todayStr,
    })
  }

  return days
})

// ── Range Helpers ────────────────────────────────────────────────────────────

// Active effective range (accounts for hover preview while selecting end)
const effectiveRange = computed(() => {
  const start = props.start
  const end = props.end

  if (isSelectingEnd.value && hoverDate.value) {
    if (hoverDate.value < start) {
      return { start: hoverDate.value, end: start }
    }
    return { start, end: hoverDate.value }
  }

  return {
    start: start || end,
    end: end || start,
  }
})

function isSingleDay(dateStr) {
  const { start, end } = effectiveRange.value
  return start === end && dateStr === start
}

function isRangeStart(dateStr) {
  const { start, end } = effectiveRange.value
  return start !== end && dateStr === start
}

function isRangeEnd(dateStr) {
  const { start, end } = effectiveRange.value
  return start !== end && dateStr === end
}

function isBetween(dateStr) {
  const { start, end } = effectiveRange.value
  if (!start || !end || start === end) return false
  return dateStr > start && dateStr < end
}

// ── Selection Handlers ───────────────────────────────────────────────────────

function handleDateClick(dateStr) {
  if (!isSelectingEnd.value) {
    // 1st click: set start date, clear end date, wait for 2nd click
    emit('update:start', dateStr)
    emit('update:end', dateStr)
    isSelectingEnd.value = true
    hoverDate.value = null
  } else {
    // 2nd click: set end date, swap if earlier than start
    if (dateStr < props.start) {
      emit('update:start', dateStr)
      emit('update:end', props.start)
    } else {
      emit('update:end', dateStr)
    }
    isSelectingEnd.value = false
    hoverDate.value = null
  }
}

function handleDateHover(dateStr) {
  if (isSelectingEnd.value) {
    hoverDate.value = dateStr
  }
}

function selectToday() {
  const todayStr = new Date().toISOString().slice(0, 10)
  emit('update:start', todayStr)
  emit('update:end', todayStr)
  const d = new Date()
  viewYear.value = d.getFullYear()
  viewMonth.value = d.getMonth()
  isSelectingEnd.value = false
  hoverDate.value = null
}

// ── Formatted Output for Trigger ─────────────────────────────────────────────

const formattedRangeText = computed(() => {
  if (!props.start) return 'Pilih Tanggal Event'

  const [sY, sM, sD] = props.start.split('-').map(Number)
  const [eY, eM, eD] = (props.end || props.start).split('-').map(Number)

  if (!props.end || props.start === props.end) {
    return `${sD} ${SHORT_MONTHS[sM - 1]} ${sY}`
  }
  if (sY === eY && sM === eM) {
    return `${sD}–${eD} ${SHORT_MONTHS[sM - 1]} ${sY}`
  }
  if (sY === eY) {
    return `${sD} ${SHORT_MONTHS[sM - 1]} – ${eD} ${SHORT_MONTHS[eM - 1]} ${sY}`
  }
  return `${sD} ${SHORT_MONTHS[sM - 1]} ${sY} – ${eD} ${SHORT_MONTHS[eM - 1]} ${eY}`
})

const totalDays = computed(() => {
  if (!props.start || !props.end) return 1
  const d1 = new Date(props.start + 'T00:00:00')
  const d2 = new Date(props.end + 'T00:00:00')
  const diffTime = Math.abs(d2 - d1)
  return Math.round(diffTime / (1000 * 60 * 60 * 24)) + 1
})

// ── Click Outside & Keyboard Listener ────────────────────────────────────────

function handleClickOutside(event) {
  if (pickerRef.value && !pickerRef.value.contains(event.target)) {
    closePicker()
  }
}

function handleKeydown(event) {
  if (event.key === 'Escape' && isOpen.value) {
    closePicker()
  }
}

onMounted(() => {
  document.addEventListener('click', handleClickOutside)
  document.addEventListener('keydown', handleKeydown)
})

onUnmounted(() => {
  document.removeEventListener('click', handleClickOutside)
  document.removeEventListener('keydown', handleKeydown)
})
</script>

<template>
  <div ref="pickerRef" class="relative w-full">
    <!-- Trigger Button -->
    <button
      type="button"
      @click="togglePicker"
      :class="[
        'w-full bg-slate-700 hover:bg-slate-700/80 border text-slate-100 rounded-lg px-3 py-2 text-sm flex items-center justify-between transition-all duration-150 cursor-pointer text-left',
        isOpen ? 'border-emerald-500 ring-2 ring-emerald-500/20' : 'border-slate-600 hover:border-slate-500',
      ]"
    >
      <div class="flex items-center gap-2.5 min-w-0">
        <CalendarIcon class="w-4 h-4 text-emerald-400 shrink-0" />
        <span class="font-medium text-slate-100 truncate">
          {{ formattedRangeText }}
        </span>
      </div>

      <span
        class="shrink-0 ml-2 bg-emerald-500/15 border border-emerald-500/30 text-emerald-400 text-xs px-2 py-0.5 rounded-full font-mono font-medium"
      >
        {{ totalDays }} hari
      </span>
    </button>

    <!-- Popover Calendar UI -->
    <Transition
      enter-active-class="transition duration-150 ease-out"
      enter-from-class="transform scale-95 opacity-0 -translate-y-1"
      enter-to-class="transform scale-100 opacity-100 translate-y-0"
      leave-active-class="transition duration-100 ease-in"
      leave-from-class="transform scale-100 opacity-100 translate-y-0"
      leave-to-class="transform scale-95 opacity-0 -translate-y-1"
    >
      <div
        v-if="isOpen"
        class="absolute left-0 top-full mt-2 z-50 w-72 sm:w-80 bg-slate-900 border border-slate-700 rounded-2xl shadow-2xl p-4 flex flex-col gap-3"
      >
        <!-- Popover Header: Month / Year Navigation -->
        <div class="flex items-center justify-between">
          <button
            type="button"
            @click="prevMonth"
            class="p-1.5 rounded-lg hover:bg-slate-800 text-slate-400 hover:text-white transition-colors"
            title="Bulan sebelumnya"
          >
            <ChevronLeft class="w-4 h-4" />
          </button>

          <span class="text-sm font-bold text-slate-100 select-none">
            {{ currentMonthYearLabel }}
          </span>

          <button
            type="button"
            @click="nextMonth"
            class="p-1.5 rounded-lg hover:bg-slate-800 text-slate-400 hover:text-white transition-colors"
            title="Bulan berikutnya"
          >
            <ChevronRight class="w-4 h-4" />
          </button>
        </div>

        <!-- Day Headers -->
        <div class="grid grid-cols-7 text-center select-none">
          <span
            v-for="d in DAY_HEADERS"
            :key="d"
            class="text-[11px] font-semibold text-slate-500 uppercase tracking-wider py-1"
          >
            {{ d }}
          </span>
        </div>

        <!-- Calendar Days Grid -->
        <div class="grid grid-cols-7 gap-y-1">
          <div
            v-for="cell in calendarDays"
            :key="cell.dateStr"
            class="relative py-0.5 flex items-center justify-center"
            @mouseenter="handleDateHover(cell.dateStr)"
          >
            <!-- Continuous Connecting Range Highlight Strip -->
            <div
              v-if="isRangeStart(cell.dateStr) || isRangeEnd(cell.dateStr) || isBetween(cell.dateStr)"
              :class="[
                'absolute inset-y-0.5 bg-emerald-500/20 pointer-events-none',
                isRangeStart(cell.dateStr) ? 'left-1/2 right-0' : '',
                isRangeEnd(cell.dateStr) ? 'left-0 right-1/2' : '',
                isBetween(cell.dateStr) ? 'left-0 right-0' : '',
              ]"
            />

            <!-- Date Button -->
            <button
              type="button"
              @click="handleDateClick(cell.dateStr)"
              :class="[
                'relative z-10 w-9 h-8 text-xs font-semibold flex items-center justify-center transition-all duration-150',
                isSingleDay(cell.dateStr)
                  ? 'bg-emerald-500 text-slate-950 font-bold rounded-lg shadow-sm shadow-emerald-500/30 scale-95'
                  : isRangeStart(cell.dateStr)
                    ? 'bg-emerald-500 text-slate-950 font-bold rounded-l-lg shadow-sm shadow-emerald-500/30'
                    : isRangeEnd(cell.dateStr)
                      ? 'bg-emerald-500 text-slate-950 font-bold rounded-r-lg shadow-sm shadow-emerald-500/30'
                      : isBetween(cell.dateStr)
                        ? 'text-emerald-300 font-semibold hover:bg-emerald-500/30'
                        : cell.isCurrentMonth
                          ? 'text-slate-200 hover:bg-slate-800 rounded-lg'
                          : 'text-slate-600 hover:bg-slate-800/40 rounded-lg',
                cell.isToday && !isSingleDay(cell.dateStr) && !isRangeStart(cell.dateStr) && !isRangeEnd(cell.dateStr) && !isBetween(cell.dateStr)
                  ? 'border border-emerald-500/50 text-emerald-400 font-bold'
                  : '',
              ]"
            >
              {{ cell.dayNum }}
            </button>
          </div>
        </div>

        <!-- Footer Actions -->
        <div class="pt-2 border-t border-slate-800 flex items-center justify-between gap-2">
          <button
            type="button"
            @click="selectToday"
            class="text-xs text-slate-400 hover:text-emerald-400 px-2.5 py-1 rounded-lg hover:bg-slate-800 font-medium transition-colors"
          >
            Hari Ini
          </button>

          <button
            type="button"
            @click="closePicker"
            class="flex items-center gap-1 bg-emerald-500 hover:bg-emerald-400 text-slate-950 text-xs font-bold px-3 py-1.5 rounded-lg transition-colors shadow-sm"
          >
            <Check class="w-3.5 h-3.5" />
            Selesai
          </button>
        </div>
      </div>
    </Transition>
  </div>
</template>

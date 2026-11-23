import { ref } from 'vue'
import { supabase } from './supabase'

// Module-level shared reactive state across the application
const events = ref([])
const activeEvent = ref(null)
const selectedEventId = ref(sessionStorage.getItem('popuppos_selected_event_id') || '')
const loadingEvents = ref(false)

function isEventActive(e) {
  if (!e) return false
  const isCompleted = (e.status || '').toUpperCase() === 'COMPLETED'
  const isActive = e.status ? (e.status.toUpperCase() === 'ACTIVE') : (e.is_active !== false)
  return isActive && !isCompleted
}

/**
 * Composable for managing POS events.
 * Provides reactive state and async operations for the events table.
 */
export function useEvents() {
  /**
   * Set the currently active event (used across the app to scope transactions).
   * @param {Object|null} event
   */
  function setActiveEvent(event) {
    activeEvent.value = event
    selectedEventId.value = event?.id || ''
    if (event?.id) {
      sessionStorage.setItem('popuppos_selected_event_id', event.id)
    } else {
      sessionStorage.removeItem('popuppos_selected_event_id')
    }
  }

  /**
   * Set active event by its UUID id.
   * @param {string} id
   */
  function selectEventId(id) {
    selectedEventId.value = id
    if (id) {
      sessionStorage.setItem('popuppos_selected_event_id', id)
      activeEvent.value = events.value.find(e => e.id === id) || null
    } else {
      sessionStorage.removeItem('popuppos_selected_event_id')
      activeEvent.value = null
    }
  }

  /**
   * Fetch all events from Supabase, ordered by most recent first.
   * Populates the `events` ref and auto-selects active event if needed.
   */
  async function fetchEvents() {
    loadingEvents.value = true
    try {
      const { data, error } = await supabase
        .from('events')
        .select('*')
        .order('created_at', { ascending: false })

      if (error) {
        console.error('[useEvents] fetchEvents error:', error.message)
        throw error
      }

      events.value = data ?? []

      // If selectedEventId exists in list, sync activeEvent
      if (selectedEventId.value) {
        const found = events.value.find(e => e.id === selectedEventId.value)
        if (found) {
          activeEvent.value = found
          return events.value
        }
      }

      // Otherwise auto-select the first ACTIVE event or the latest event
      if (events.value.length > 0) {
        const activeOne = events.value.find(isEventActive) || events.value[0]
        setActiveEvent(activeOne)
      } else {
        setActiveEvent(null)
      }

      return events.value
    } finally {
      loadingEvents.value = false
    }
  }

  /**
   * Create a new event and return it.
   * @param {Object} payload - Fields matching the events table schema
   * @returns {Object} The newly created event row
   */
  async function createEvent(payload) {
    const { data, error } = await supabase
      .from('events')
      .insert(payload)
      .select()
      .single()

    if (error) {
      console.error('[useEvents] createEvent error:', error.message)
      throw error
    }

    // Prepend to local list so UI updates immediately
    events.value = [data, ...events.value]
    return data
  }

  /**
   * Update an existing event settings.
   * @param {string} id - Event UUID
   * @param {Object} payload - Fields to update
   * @returns {Object} The updated event row
   */
  async function updateEvent(id, payload) {
    const { data, error } = await supabase
      .from('events')
      .update(payload)
      .eq('id', id)
      .select()
      .single()

    if (error) {
      console.error('[useEvents] updateEvent error:', error.message)
      throw error
    }

    const index = events.value.findIndex(e => e.id === id)
    if (index !== -1) {
      events.value[index] = data
    }
    if (activeEvent.value?.id === id) {
      activeEvent.value = data
    }
    return data
  }

  return {
    events,
    activeEvent,
    selectedEventId,
    loadingEvents,
    setActiveEvent,
    selectEventId,
    fetchEvents,
    createEvent,
    updateEvent,
    isEventActive
  }
}

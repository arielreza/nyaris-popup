import { ref } from 'vue'
import { supabase } from './supabase'

/**
 * Composable for managing POS events.
 * Provides reactive state and async operations for the events table.
 */
export function useEvents() {
  const events = ref([])
  const activeEvent = ref(null)

  /**
   * Set the currently active event (used across the app to scope transactions).
   * @param {Object|null} event
   */
  function setActiveEvent(event) {
    activeEvent.value = event
  }

  /**
   * Fetch all events from Supabase, ordered by most recent first.
   * Populates the `events` ref.
   */
  async function fetchEvents() {
    const { data, error } = await supabase
      .from('events')
      .select('*')
      .order('created_at', { ascending: false })

    if (error) {
      console.error('[useEvents] fetchEvents error:', error.message)
      throw error
    }

    events.value = data ?? []
    return events.value
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
    setActiveEvent,
    fetchEvents,
    createEvent,
    updateEvent
  }
}

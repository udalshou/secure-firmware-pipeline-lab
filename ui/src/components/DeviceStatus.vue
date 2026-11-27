<script setup lang="ts">
import { onMounted, ref } from 'vue'

interface Status {
  version: string
  uptime_seconds: number
}

const status = ref<Status | null>(null)
const error = ref<string | null>(null)

async function load(): Promise<void> {
  try {
    const response = await fetch('/status')
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`)
    }
    status.value = (await response.json()) as Status
    error.value = null
  } catch (e) {
    error.value = e instanceof Error ? e.message : String(e)
  }
}

onMounted(load)
</script>

<template>
  <section>
    <h2>Device status</h2>
    <p v-if="error">
      Status unavailable: {{ error }}
    </p>
    <dl v-else-if="status">
      <dt>Firmware API version</dt>
      <dd>{{ status.version }}</dd>
      <dt>Uptime</dt>
      <dd>{{ status.uptime_seconds }} s</dd>
    </dl>
    <p v-else>
      Loading…
    </p>
    <button
      type="button"
      @click="load"
    >
      Refresh
    </button>
  </section>
</template>

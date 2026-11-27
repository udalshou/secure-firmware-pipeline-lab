import vue from '@vitejs/plugin-vue'
import { defineConfig } from 'vite'

// In dev, forward API calls to a locally running `lab-api` (default port 8080).
// On the device, the API serves the built UI itself, so no proxy is involved.
const api = 'http://127.0.0.1:8080'

export default defineConfig({
  plugins: [vue()],
  server: {
    proxy: { '/status': api, '/health': api },
  },
})

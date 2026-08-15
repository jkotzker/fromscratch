import react from '@vitejs/plugin-react';
import { defineConfig } from 'electron-vite';

// Main and preload dependencies (node-localstorage, minimist, compare-versions) are pure JS and
// get bundled into out/, so the packaged app ships without a node_modules directory.
export default defineConfig({
  main: {
    build: {
      minify: false,
    },
  },
  preload: {
    build: {
      minify: false,
    },
  },
  renderer: {
    plugins: [react()],
  },
});

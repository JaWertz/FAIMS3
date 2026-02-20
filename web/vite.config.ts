import path from 'path';
import react from '@vitejs/plugin-react-swc';
import {defineConfig} from 'vite';
import {tanstackRouter} from '@tanstack/router-plugin/vite';

const ALLOWED_HOSTS = (
  process.env.VITE_ALLOWED_HOSTS ??
  'fe6103-c0005.sna94.uni-tuebingen.de,localhost,127.0.0.1'
)
  .split(',')
  .map(host => host.trim())
  .filter(Boolean);

export default defineConfig({
  // Just a hack to get this to typecheck - works fine??
  plugins: [
    tanstackRouter({
      target: 'react',
      autoCodeSplitting: true,
    }),
    react(),
  ],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  server: {
    port: 3001,
    host: true,
    strictPort: true,
    allowedHosts: ALLOWED_HOSTS,
    cors: true,
    fs: {allow: ['..']},
  },
  preview: {
    port: 3001,
    host: true,
    strictPort: true,
    allowedHosts: ALLOWED_HOSTS,
  },
  optimizeDeps: {
    include: [
      '@mui/material',
      '@mui/icons-material',
      '@emotion/react',
      '@emotion/styled',
      '@emotion/react/jsx-runtime',
    ],
    exclude: [],
  },
  // Polyfill global in case of weird importing going on!
  define: {
    global: 'globalThis',
    // Replace __APP_VERSION__ with package.json version at build time
    __APP_VERSION__: JSON.stringify(process.env.npm_package_version),
  },
});

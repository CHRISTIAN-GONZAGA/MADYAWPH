import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.gloretto.hotelhms',
  appName: 'Gloretto Hotel HMS',
  webDir: 'www',
  server: {
    url: 'https://madyawph.onrender.com',
    cleartext: false,
    androidScheme: 'https',
    allowNavigation: ['madyawph.onrender.com'],
  },
};

export default config;

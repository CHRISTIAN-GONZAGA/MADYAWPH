import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.gloretto.hotelhms',
  appName: 'Gloretto Hotel HMS',
  webDir: 'www',
  server: {
    url: 'https://madyawph.onrender.com',
    cleartext: false,
  },
};

export default config;

import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.gloretto.hotelhms',
  appName: 'Gloretto Hotel HMS',
  webDir: 'www',
  server: {
    url: 'http://192.168.1.224:8000',
    cleartext: true,
  },
};

export default config;

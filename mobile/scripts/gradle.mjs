/**
 * Runs android/gradlew with the given task (e.g. assembleDebug) on Windows and Unix.
 */
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const task = process.argv[2] || 'assembleDebug';
const root = path.dirname(fileURLToPath(import.meta.url));
const androidDir = path.join(root, '..', 'android');
const isWin = process.platform === 'win32';
const gradle = isWin ? 'gradlew.bat' : './gradlew';
const r = spawnSync(gradle, [task], {
  cwd: androidDir,
  stdio: 'inherit',
  shell: isWin,
});
process.exit(r.status ?? 1);

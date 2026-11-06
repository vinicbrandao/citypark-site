import { cpSync, mkdirSync } from 'node:fs';
mkdirSync('dist/assets', { recursive: true });
cpSync('assets', 'dist/assets', { recursive: true });

import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  // Puppeteer and the scrapers must run as plain Node modules, not bundled.
  serverExternalPackages: ['israeli-bank-scrapers', 'puppeteer'],
};

export default nextConfig;

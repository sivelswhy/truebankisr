import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  // Puppeteer and the scrapers must run as plain Node modules, not bundled.
  serverExternalPackages: ['israeli-bank-scrapers', 'puppeteer'],
  // The floating "N" badge would sit on the tab bar.
  devIndicators: false,
};

export default nextConfig;

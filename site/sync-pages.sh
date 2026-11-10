#!/bin/sh
# Copies the static pages into docs/webapp/ for GitHub Pages. The API relay
# (api/max.js, api/leumi.js) stays on Vercel only: GitHub Pages can't run it.
# Run this after any change to one of these files.
set -e
cd "$(dirname "$0")"
for f in index.html max.html leumi.html style.css shared.js app.js max-login.js leumi-login.js lib.js demo.js leumi.js icons.js; do
  cp "$f" "../docs/webapp/$f"
done
echo "Copied into ../docs/webapp"

#!/bin/sh
# Copies the static page into docs/webapp/ for GitHub Pages. The API relay
# (api/max.js) stays on Vercel only: GitHub Pages can't run it. Run this
# after any change to index.html, app.js, lib.js, demo.js, leumi.js or icons.js.
set -e
cd "$(dirname "$0")"
for f in index.html app.js lib.js demo.js leumi.js icons.js; do
  cp "$f" "../docs/webapp/$f"
done
echo "Copied into ../docs/webapp"

// Adds a build to altstore-source.json (AltStore / SideStore source) so the
// app shows up as an update on the phone.
// Usage: node ios/altstore-source.mjs <version> <build> <ipa path> <download URL> <notes file>
import { readFileSync, statSync, writeFileSync } from "node:fs";

const [version, buildVersion, ipa, downloadURL, notesFile] = process.argv.slice(2);
const repo = "https://github.com/sivelswhy/truebankisr";
const raw = "https://raw.githubusercontent.com/sivelswhy/truebankisr/main";
const iconURL = `${raw}/ios/TrueBalance/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png`;
const file = new URL("../altstore-source.json", import.meta.url);
const keep = 10; // older builds stay on the Releases page

let source;
try {
  source = JSON.parse(readFileSync(file, "utf8"));
} catch {
  source = {
    name: "True Balance",
    identifier: "il.truebalance.source",
    sourceURL: `${raw}/altstore-source.json`,
    subtitle: "Your real balance across Leumi and Max.",
    description: "AltStore / SideStore source for True Balance. Add it to get one-tap updates of the sideloaded iPhone app.",
    iconURL,
    website: repo,
    tintColor: "007AFF",
    apps: [
      {
        name: "True Balance",
        bundleIdentifier: "il.truebalance.app",
        developerName: "sivelswhy",
        subtitle: "Your real balance across Leumi and Max.",
        localizedDescription: "Shows what you really have left: your Leumi balance minus what Max will charge.",
        iconURL,
        tintColor: "007AFF",
        category: "utilities",
        screenshotURLs: [],
        versions: [],
      },
    ],
  };
}

// Commit message title only; the trailer lines don't belong on the phone.
const notes = readFileSync(notesFile, "utf8").split("\n")[0].trim();
const app = source.apps[0];
app.versions = [
  {
    version,
    buildVersion,
    date: new Date().toISOString(),
    localizedDescription: notes,
    downloadURL,
    size: statSync(ipa).size,
    minOSVersion: "18.0",
  },
  ...app.versions.filter((v) => v.buildVersion !== buildVersion),
].slice(0, keep);

writeFileSync(file, JSON.stringify(source, null, 2) + "\n");

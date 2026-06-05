const { execFileSync } = require("node:child_process");
const { mkdirSync } = require("node:fs");
const { join } = require("node:path");

const root = __dirname;
const renders = join(root, "renders");
const outputPath = join(renders, "permission-modules.mp4");

mkdirSync(renders, { recursive: true });
mkdirSync(join(root, ".swift-module-cache"), { recursive: true });

execFileSync("swift", ["-module-cache-path", join(root, ".swift-module-cache"), join(root, "render.swift")], { stdio: "inherit" });

execFileSync(
  "ffmpeg",
  [
    "-y",
    "-hide_banner",
    "-framerate",
    "30",
    "-i",
    join(root, "frames", "frame-%04d.png"),
    "-f",
    "lavfi",
    "-i",
    "anullsrc=channel_layout=stereo:sample_rate=48000",
    "-t",
    "15",
    "-c:v",
    "libx264",
    "-pix_fmt",
    "yuv420p",
    "-c:a",
    "aac",
    "-b:a",
    "128k",
    "-movflags",
    "+faststart",
    outputPath,
  ],
  { stdio: "inherit" },
);

console.log(outputPath);

const { withDangerousMod } = require('expo/config-plugins');
const fs = require('fs');
const path = require('path');

const POD_NAME = 'DualCamera';
const POD_LINE = `  pod '${POD_NAME}', :path => './LocalPods/${POD_NAME}'`;
const GPUPIXEL_FRAMEWORK_NAME = 'gpupixel.framework';
const FMT_COMPAT_MARKER = 'Fix fmt 11 constexpr format-string compilation';
const FMT_COMPAT_BLOCK = [
  '',
  '    # Fix fmt 11 constexpr format-string compilation on newer Xcode/Clang.',
  '    installer.pods_project.targets.each do |target|',
  "      next unless target.name == 'fmt'",
  '',
  '      target.build_configurations.each do |config|',
  "        config.build_settings['CLANG_CXX_LANGUAGE_STANDARD'] = 'c++17'",
  "        config.build_settings['GCC_TREAT_WARNINGS_AS_ERRORS'] = 'NO'",
  '',
  "        definitions = config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= ['$(inherited)']",
  "        definitions << 'FMT_USE_NONTYPE_TEMPLATE_ARGS=0' unless definitions.include?('FMT_USE_NONTYPE_TEMPLATE_ARGS=0')",
  '      end',
  '    end',
];

module.exports = function withDualCamera(config) {
  return withDangerousMod(config, ['ios', copyNativeAndPatchPodfile]);
};

module.exports.__internal = {
  copyNativeAndPatchPodfile,
  patchPodfile,
};

function copyNativeAndPatchPodfile(config) {
  const projectRoot = config.modRequest.projectRoot;
  const podfilePath = path.join(projectRoot, 'ios', 'Podfile');
  const srcDir = path.join(projectRoot, 'native', 'LocalPods', POD_NAME);
  const destDir = path.join(projectRoot, 'ios', 'LocalPods', POD_NAME);
  const gpupixelSrc = path.join(projectRoot, 'native', 'ThirdParty', 'GPUPixel', 'ios', GPUPIXEL_FRAMEWORK_NAME);
  const gpupixelDest = path.join(destDir, 'Frameworks', GPUPIXEL_FRAMEWORK_NAME);

  if (!fs.existsSync(srcDir)) {
    throw new Error(`[withDualCamera] Missing native sources: ${srcDir}`);
  }

  if (!fs.existsSync(podfilePath)) {
    throw new Error(`[withDualCamera] Missing generated Podfile: ${podfilePath}`);
  }

  fs.rmSync(destDir, { recursive: true, force: true });
  copyRecursiveSync(srcDir, destDir);
  if (fs.existsSync(gpupixelSrc)) {
    fs.rmSync(path.dirname(gpupixelDest), { recursive: true, force: true });
    copyRecursiveSync(gpupixelSrc, gpupixelDest);
  }

  const podfile = fs.readFileSync(podfilePath, 'utf8');
  const patchedPodfile = patchPodfile(podfile);
  if (patchedPodfile !== podfile) {
    fs.writeFileSync(podfilePath, patchedPodfile, 'utf8');
  }

  return config;
}

function copyRecursiveSync(srcDir, destDir) {
  fs.mkdirSync(destDir, { recursive: true });

  for (const entry of fs.readdirSync(srcDir, { withFileTypes: true })) {
    const srcPath = path.join(srcDir, entry.name);
    const destPath = path.join(destDir, entry.name);

    if (entry.isDirectory()) {
      copyRecursiveSync(srcPath, destPath);
    } else if (entry.isFile()) {
      fs.copyFileSync(srcPath, destPath);
    }
  }
}

function patchPodfile(podfile) {
  const newline = podfile.includes('\r\n') ? '\r\n' : '\n';
  const lines = podfile.split(/\r?\n/);
  const targetStart = lines.findIndex((line) => /^\s*target\s+['"][^'"]+['"]\s+do\s*$/.test(line));

  if (targetStart === -1) {
    throw new Error(`[withDualCamera] Could not find an iOS target block in Podfile`);
  }

  const targetEnd = findMatchingEnd(lines, targetStart);
  if (targetEnd === -1) {
    throw new Error(`[withDualCamera] Could not find the end of the iOS target block in Podfile`);
  }

  if (!podfile.includes(`pod '${POD_NAME}'`)) {
    const useExpoModulesIndex = findLineInRange(lines, targetStart + 1, targetEnd, /^\s*use_expo_modules!(?:\s|\(|$)/);
    const postInstallIndex = findLineInRange(lines, targetStart + 1, targetEnd, /^\s*post_install\s+do\b/);
    const insertAt = useExpoModulesIndex !== -1
      ? useExpoModulesIndex + 1
      : (postInstallIndex !== -1 ? postInstallIndex : targetEnd);

    lines.splice(insertAt, 0, POD_LINE);
  }

  patchFmtCompatibility(lines, targetStart);
  return lines.join(newline);
}

function patchFmtCompatibility(lines, targetStart) {
  if (lines.some((line) => line.includes(FMT_COMPAT_MARKER))) {
    return;
  }

  const targetEnd = findMatchingEnd(lines, targetStart);
  if (targetEnd === -1) {
    throw new Error(`[withDualCamera] Could not find the end of the iOS target block in Podfile`);
  }

  const postInstallIndex = findLineInRange(lines, targetStart + 1, targetEnd, /^\s*post_install\s+do\b/);
  if (postInstallIndex === -1) {
    throw new Error(`[withDualCamera] Could not find post_install block in Podfile`);
  }

  const postInstallEnd = findMatchingEnd(lines, postInstallIndex);
  if (postInstallEnd === -1) {
    throw new Error(`[withDualCamera] Could not find the end of the post_install block in Podfile`);
  }

  lines.splice(postInstallEnd, 0, ...FMT_COMPAT_BLOCK);
}

function findLineInRange(lines, start, end, pattern) {
  for (let i = start; i < end; i += 1) {
    if (pattern.test(lines[i])) {
      return i;
    }
  }
  return -1;
}

function findMatchingEnd(lines, startIndex) {
  let depth = 0;

  for (let i = startIndex; i < lines.length; i += 1) {
    const code = lines[i].replace(/#.*/, '').trim();
    if (!code) {
      continue;
    }

    if (opensRubyBlock(code)) {
      depth += 1;
    }

    if (/^end\s*$/.test(code)) {
      depth -= 1;
      if (depth === 0) {
        return i;
      }
    }
  }

  return -1;
}

function opensRubyBlock(code) {
  return /^(target|abstract_target|post_install|pre_install)\b.*\bdo\b/.test(code)
    || /^(if|unless|case|begin|class|module|def|for|while|until)\b/.test(code)
    || /\bdo\s*(\|.*\|)?\s*$/.test(code);
}

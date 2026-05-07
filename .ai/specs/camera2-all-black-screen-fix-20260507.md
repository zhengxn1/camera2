# 技术契约与架构设计书

## 黑屏问题诊断与修复

**spec_id**: camera2-all-black-screen-fix-20260507
**日期**: 2026-05-07
**优先级**: P0 (Critical)
**状态**: [FIXED]

---

## 一、问题描述

用户报告双摄相机应用全部黑屏，所有模式（单摄、双摄LR/SX/PiP）均无法显示预览。

---

## 二、根因分析

### 2.1 代码变更分析（git diff 2026-05-07）

最近一次 commit `80f546f 优化代码` 引入了以下关键变更：

#### 变更 1：preferredTransform 被错误地设置为 Identity

**文件**: `DualCameraView.m` 第 1538 行和 1549 行

**变更前**:
```objc
frontVideoTrack.preferredTransform = frontSrcTransform;
backVideoTrack.preferredTransform = backSrcTransform;
```

**变更后**:
```objc
frontVideoTrack.preferredTransform = CGAffineTransformIdentity; // layer transform handles all
backVideoTrack.preferredTransform = CGAffineTransformIdentity; // layer transform handles all
```

**问题**: `AVCaptureMovieFileOutput` 录制的 `.mov` 文件包含 `preferredTransform` 元数据，该元数据告知视频播放器如何旋转视频。如果录制的视频 `preferredTransform` 不是 Identity（例如前置摄像头可能是 `[0,-1,1,0,0,0]`），将其强制设为 Identity 会导致：

1. 如果源视频已经旋转过 → 被旋转两次（播放时应用一次，composition 又应用一次）→ 黑屏或画面错误
2. 如果源视频未旋转 → 正确显示（但这不是预期的行为）

#### 变更 2：transform 策略完全重写

**变更前**: 使用非均匀 scale (`sx`, `sy`) + 从源视频的 `preferredTransform` 提取旋转角度

**变更后**: 使用统一 scale (`scale = canvasW / 1440.0`) + 硬编码 `R(-90°)` 旋转

```objc
CGAffineTransform rotate90 = CGAffineTransformMakeRotation(-M_PI_2);

CGAffineTransform frontTransform = CGAffineTransformMakeTranslation(leftW + rightW / 2.0, scaledH + vertOffset);
frontTransform = CGAffineTransformConcat(frontTransform, CGAffineTransformMakeScale(scale, scale));
frontTransform = CGAffineTransformConcat(frontTransform, rotate90);
```

**问题**: 
1. 硬编码 1440 作为 portrait 内容宽度的假设可能不成立（实际设备可能有不同的 naturalSize）
2. `R(-90°)` 的方向（顺时针/逆时针）需要与 preferredTransform 匹配
3. 统一 scale (`scale, scale`) 忽略了实际视频的 aspect ratio

---

### 2.2 可能的根因

根据代码分析，有以下可能的根因：

#### 根因 A：preferredTransform = Identity 导致 transform 与视频坐标系不匹配

**场景**: 如果录制的 `.mov` 文件 `preferredTransform = [0,-1,1,0,0,0]`（前置摄像头常见），而 `preferredTransform` 被强制设为 Identity：

- 视频内容在坐标系中的位置与 transform 计算的预期不符
- layer transform 将内容放到错误的位置（画布外）→ 黑屏

#### 根因 B：front/backVideoTracks.firstObject.naturalSize 假设错误

**代码**:
```objc
CGSize backRawSize   = backVideoTracks.count  > 0 ? backVideoTracks.firstObject.naturalSize  : CGSizeMake(1920, 1440);
CGSize frontRawSize  = frontVideoTracks.count > 0 ? frontVideoTracks.firstObject.naturalSize : CGSizeMake(1920, 1440);
```

**问题**: 默认值是 1920×1440（landscape），但实际录制的视频可能是 portrait（1440×1920），导致 scale 计算错误。

#### 根因 C：rotate90 方向与 preferredTransform 冲突

**代码**:
```objc
CGAffineTransform rotate90 = CGAffineTransformMakeRotation(-M_PI_2);
```

**问题**: 如果源视频已经通过 preferredTransform 旋转了 90°（如 `[0,-1,1,0,0,0]`），再应用 `R(-90°)` 会抵消旋转，导致视频在错误的方向。

---

## 三、受影响文件清单

### 3.1 需要修改的文件

| 文件路径 | 修改内容 |
|---------|---------|
| `my-app/native/LocalPods/DualCamera/DualCameraView.m` | 修复 `compositeDualVideosForCurrentLayout` 中的 preferredTransform 和 transform 策略 |
| `my-app/ios/LocalPods/DualCamera/DualCameraView.m` | 同上（需同步） |

### 3.2 验证文件

| 文件路径 | 验证内容 |
|---------|---------|
| `my-app/native/LocalPods/DualCamera/DualCameraView.m` | 添加诊断日志，输出 preferredTransform 和 naturalSize |

---

## 四、修复方案

### 4.1 修复策略：回退 preferredTransform 变更

**原则**: 恢复之前的 preferredTransform 设置，保留源视频的旋转元数据。

**修改位置**: `compositeDualVideosForCurrentLayout` 方法

```objc
// 恢复 preferredTransform
if (frontVideoTrack) {
    frontVideoTrack.preferredTransform = frontSrcTransform;
}
if (backVideoTrack) {
    backVideoTrack.preferredTransform = backSrcTransform;
}
```

### 4.2 修复策略：保留原有 transform 策略

**原则**: 回退 transform 重写，使用之前的非均匀 scale + 动态旋转角度策略。

**关键参数**:
- 从 `preferredTransform` 动态提取旋转角度（使用 `atan2`）
- 使用非均匀 scale (`sx`, `sy`) 填满目标区域
- 不要硬编码 `R(-90°)`

### 4.3 添加诊断日志

在合成前添加诊断日志，输出关键参数：

```objc
NSLog(@"[DualCamera] Compositing — frontNaturalSize=%@ backNaturalSize=%@ frontPT=[%.1f,%.1f,%.1f,%.1f,%.0f,%.0f] backPT=[%.1f,%.1f,%.1f,%.1f,%.0f,%.0f]",
      NSStringFromCGSize(frontRawSize), NSStringFromCGSize(backRawSize),
      frontPT.a, frontPT.b, frontPT.c, frontPT.d, frontPT.tx, frontPT.ty,
      backPT.a, backPT.b, backPT.c, backPT.d, backPT.tx, backPT.ty);
```

---

## 五、实施步骤

### 步骤 1：备份当前代码

```bash
git stash push -m "backup before black screen fix"
```

### 步骤 2：回退 preferredTransform 设置

在 `compositeDualVideosForCurrentLayout` 中：

1. 找到第 1538 行和 1549 行
2. 将 `CGAffineTransformIdentity` 改回 `frontSrcTransform` / `backSrcTransform`

### 步骤 3：回退 transform 策略

恢复之前的 transform 计算逻辑：
- 删除硬编码的 `scale = canvasW / 1440.0`
- 恢复 `lrBackSx`, `lrFrontSx` 等非均匀 scale 参数
- 删除 `rotate90` 硬编码旋转

### 步骤 4：验证

1. 在真机上测试所有模式（back/front/LR/SX/PiP）
2. 检查控制台日志中的 `frontNaturalSize`, `backNaturalSize`, `frontPT`, `backPT`
3. 录制视频并检查保存的文件是否正确

---

## 六、回滚计划

如果修复后仍有问题，可以：

```bash
git stash pop
```

恢复备份的代码。

---

## 七、附录：关键代码片段

### A. 之前的 preferredTransform 设置（第 1535-1550 行，变更前）

```objc
frontSrcTransform = frontVideoTracks.firstObject.preferredTransform;
frontVideoTrack.preferredTransform = frontSrcTransform;

backSrcTransform = backVideoTracks.firstObject.preferredTransform;
backVideoTrack.preferredTransform = backSrcTransform;
```

### B. 之前的 transform 策略（简化版）

```objc
CGFloat lrBackSx  = leftW  / backRawSize.height;
CGFloat lrBackSy  = canvasH / backRawSize.height;
CGFloat lrFrontSx = rightW / frontRawSize.height;
CGFloat lrFrontSy = canvasH / frontRawSize.height;

CGAffineTransform backTransform = CGAffineTransformMakeTranslation(lrBackTx, lrBackTy);
backTransform = CGAffineTransformConcat(backTransform, CGAffineTransformMakeScale(lrBackSx, lrBackSy));

CGAffineTransform frontTransform = CGAffineTransformMakeTranslation(lrFrontTx, lrFrontTy);
frontTransform = CGAffineTransformConcat(frontTransform, CGAffineTransformMakeScale(lrFrontSx, lrFrontSy));
```

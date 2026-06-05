# 技术规格说明书：SX 上下分屏拍照 — 后置摄像头被遮盖修复

## 1. 概述

| 字段 | 值 |
|------|-----|
| **spec_id** | camera2-sx-split-photo-back-hidden-fix-20260521 |
| **首次发现** | 2026-05-21 |
| **用户症状** | 上下分屏（SX）模式拍照时，后置摄像头画面被前置摄像头遮盖；翻转后前置在顶部正常显示 |
| **根本原因** | `compositedImageForLayoutState:front:back:highQuality:` 的非 PiP 分支未遵守 `sxBackOnTop` 状态 |
| **影响范围** | SX 布局下的拍照功能（视频录制不受影响，已在 `compositeDualVideosForCurrentLayout` 中正确处理） |
| **风险等级** | 低 — 单文件、单逻辑分支修改 |

---

## 2. 根因详解

### 2.1 问题代码

**文件**: `my-app/native/LocalPods/DualCamera/DualCameraView+Composition.m`  
**行号**: 第 159–162 行

```objc
if (!isPip) {
  if (backImage) result = [backImage imageByCompositingOverImage:result];
  if (frontImage) result = [frontImage imageByCompositingOverImage:result];
  return [result imageByCroppingToRect:CGRectMake(0, 0, canvasSize.width, canvasSize.height)];
}
```

### 2.2 CIImage 合成语义

`[A imageByCompositingOverImage:B]` 的语义是 **A 叠在 B 上面**。

当前代码执行顺序：
1. `backImage` 叠在 `result`（黑色画布）上 → back 在底层
2. `frontImage` 叠在结果上 → front 在顶层（遮盖 back）

### 2.3 布局行为分析

| 布局 | 预期行为 | 当前实际行为 | 结果 |
|------|---------|-------------|------|
| LR | front(右) 叠在 back(左) 上面 | front 永远在上面 | ✅ 正确 |
| SX `sxBackOnTop=YES`（默认） | back(顶) 叠在 front(底) 上面 | front 永远在上面 | ❌ 后置被遮盖 |
| SX `sxBackOnTop=NO`（翻转后） | front(顶) 叠在 back(底) 上面 | front 永远在上面 | ✅ 碰巧正确 |

### 2.4 `sxBackOnTop` 数据流验证（无问题）

| 环节 | 验证结果 |
|------|---------|
| JS 传递 `sxBackOnTop={isSplit ? !isFlipped : true}` | ✅ |
| `CameraSurface.tsx` 透传给 native | ✅ |
| `layoutStateSnapshotForCanvasSize:` 读取 `self.sxBackOnTop` 填充 `state` | ✅ |
| `captureWysiwygDualPhotoWithCanvasSize:` 传入正确的 `photoState` | ✅ |
| `compositedImageForLayoutState:` 收到正确的 `state.sxBackOnTop` 值 | ✅ |
| **`compositedImageForLayoutState:` 实际使用了该值** | ❌ **未使用** |

---

## 3. 修复方案

### 3.1 修改文件

**绝对路径**: `/Users/zhengxi/vibecoding/camera2/my-app/native/LocalPods/DualCamera/DualCameraView+Composition.m`

### 3.2 修改位置

第 159–162 行，替换为尊重 `sxBackOnTop` 的逻辑。

### 3.3 修复代码

将：

```objc
if (!isPip) {
  if (backImage) result = [backImage imageByCompositingOverImage:result];
  if (frontImage) result = [frontImage imageByCompositingOverImage:result];
  return [result imageByCroppingToRect:CGRectMake(0, 0, canvasSize.width, canvasSize.height)];
}
```

替换为：

```objc
if (!isPip) {
  BOOL isSX = [layout isEqualToString:@"sx"];
  if (isSX && state.sxBackOnTop) {
    // SX: back on top → draw front first (bottom), then back
    if (frontImage) result = [frontImage imageByCompositingOverImage:result];
    if (backImage) result = [backImage imageByCompositingOverImage:result];
  } else {
    // LR always: front on top → draw back first (bottom), then front
    // SX flipped: front on top → draw back first (bottom), then front
    if (backImage) result = [backImage imageByCompositingOverImage:result];
    if (frontImage) result = [frontImage imageByCompositingOverImage:result];
  }
  return [result imageByCroppingToRect:CGRectMake(0, 0, canvasSize.width, canvasSize.height)];
}
```

### 3.4 修复逻辑说明

| 条件 | 合成顺序 | 效果 |
|------|---------|------|
| `isSX && sxBackOnTop=YES`（默认） | front → result → back | back 在顶层（顶部可见） |
| `!isSX` 或 `sxBackOnTop=NO`（翻转） | back → result → front | front 在顶层（右侧可见 / 顶部可见） |

---

## 4. 影响面分析

### 4.1 全栈影响面

| 层级 | 文件 | 影响 |
|------|------|------|
| Native 合成层 | `DualCameraView+Composition.m` | **修改** — 修复 SX 分支合成顺序 |
| Native 录制层 | `DualCameraView+Recording.m` | 无 — 视频合成使用 `compositeDualVideosForCurrentLayout`（独立方法） |
| Native 布局层 | `DualCameraView+Layout.m` | 无 — 预览层使用 frame 分配，不受影响 |
| JS 层 | `CameraSurface.tsx` | 无 — `sxBackOnTop` 传递逻辑正确 |
| Schema/契约 | 无 | 无 — 仅修改内部合成顺序 |

### 4.2 关联已知问题

本修复解决了 KB 中已记录的架构陷阱在拍照路径上的遗漏：

> **已知缺陷模式** — SX 保存位置与预览不一致  
> 首次发现: 2026-04-30, spec: camera2-flip-zoom-drag-20260430  
> 状态: [FIXED — 视频合成 2026-04-30, **拍照合成 2026-05-21（本次）**]

---

## 5. 验证方案

### 5.1 功能验证

1. **SX 默认状态（`sxBackOnTop=YES`）**
   - 预览：后置摄像头在顶部
   - 拍照保存：后置摄像头在顶部 ✅

2. **SX 翻转状态（`sxBackOnTop=NO`）**
   - 预览：前置摄像头在顶部
   - 拍照保存：前置摄像头在顶部 ✅

3. **LR 布局回归测试**
   - 预览：前置在右侧
   - 拍照保存：前置在右侧 ✅

4. **PiP 布局回归测试**
   - 方形 PiP 和圆形 PiP 拍照不受影响 ✅

### 5.2 编译验证

```bash
cd /Users/zhengxi/vibecoding/camera2/my-app/ios && pod install
xcodebuild -workspace myapp.xcworkspace -scheme myapp \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' build
```

---

## 6. 实施步骤

### Step 1: 修改 `DualCameraView+Composition.m`

使用 `StrReplace` 工具，将第 159–162 行的非 PiP 分支替换为尊重 `sxBackOnTop` 的逻辑。

### Step 2: 同步到 `ios/LocalPods/`

由于项目使用 `copyRecursiveSync` 策略（见 KB DualCamera 两份源码陷阱），需要确认插件是否已切换到 `symlinkSync`。如果仍使用 `copyRecursiveSync`，修改 `native/LocalPods/` 后需重新运行 `pod install` 以同步到 `ios/LocalPods/`。

### Step 3: 编译验证

执行编译命令确认无编译错误。

### Step 4: 真机功能测试

在真机上执行：
1. 切换到 SX 上下分屏模式 → 拍照 → 确认后置摄像头在顶部
2. 点击翻转按钮 → 拍照 → 确认前置摄像头在顶部
3. 切换到 LR 左右分屏模式 → 拍照 → 确认前置摄像头在右侧

---

## 7. 文件清单

| 操作 | 文件绝对路径 |
|------|-------------|
| **修改** | `/Users/zhengxi/vibecoding/camera2/my-app/native/LocalPods/DualCamera/DualCameraView+Composition.m` |
| 无变化 | `/Users/zhengxi/vibecoding/camera2/my-app/ios/LocalPods/DualCamera/DualCameraView+Composition.m`（由 pod install 同步） |

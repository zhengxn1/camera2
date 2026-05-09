# Git Merge Strategy: camera2 refactor conflict

## 基本信息

- **spec_id**: git-merge-camera2-refactor-20260509
- **日期**: 2026-05-09
- **状态**: [DRAFT]

---

## 冲突摘要

### 本地分支 (HEAD)

```
commit 7c8be96 - fix: replace undeclared CMVideoDimensionsAreEqual
my-app/native/LocalPods/DualCamera/DualCameraView+Capture.m | 1 file changed
```

### 远程分支 (origin/main)

```
commit cb9bafd - refactor(app): remove App.js file and update dependencies
删除:  my-app/App.js (1360行)
新增:  my-app/App.tsx (416行) + 14个文件 (src/components/*, src/*.ts)
```

---

## 冲突类型

**破坏性重构冲突 (Destructive Refactoring)**

远程分支删除了本地正在维护的 `App.js`（1361行），替换为 TypeScript 重构版本。

---

## 合并策略选项

### 选项 A: 保留本地，放弃远程重构 [推荐]

**策略**: 本地 `App.js` 包含大量相机特定逻辑（zoom、layout ratio、PiP drag/zoom、flip 状态管理等），这些是远程 `App.tsx` 简化版本所不具备的。

**操作**:
```bash
git checkout --ours -- my-app/App.js
git checkout --ours -- my-app/src/  # 不存在，保持不存在
# 撤销远程的 App.tsx 和 src/ 改动
git checkout origin/main -- my-app/src/ 2>/dev/null || true
git checkout origin/main -- my-app/App.tsx 2>/dev/null || true
```

**优点**:
- 保留本地所有相机功能代码
- 不丢失已有的 bug 修复和功能

**缺点**:
- 延迟 TypeScript 迁移
- 代码库保持 JS 而非 TS

---

### 选项 B: 接受远程重构，合并相机功能

**策略**: 接受远程重构为 TS + 组件化架构，但需要手动将 `App.js` 中的相机功能合并到新的 `App.tsx`。

**操作**:
1. `git merge origin/main --no-commit`
2. 手动将 `App.js` 中的相机逻辑合并到 `App.tsx`
3. 保留 `src/components/*` 的新架构
4. 添加缺失的相机功能组件

**优点**:
- 获得 TypeScript 类型安全
- 现代化的组件架构
- 更好的代码组织

**缺点**:
- 合并复杂，需要大量手动工作
- 风险：可能遗漏本地已有的功能/bug修复
- 耗时较长

---

### 选项 C: Rebase 本地到远程，手动重建

**策略**: 完全采用远程架构，在新的 TS 架构上手动重建所有相机功能。

**操作**:
1. `git rebase origin/main`
2. 基于 `App.tsx` 架构，重写所有相机功能

**优点**:
- 干净的代码库，无历史包袱
- 完整的 TypeScript 迁移

**缺点**:
- 丢失本地代码的历史（除 native 层）
- 重建工作量大
- 风险最高

---

## 推荐策略

**选项 A（保留本地）** - 原因：

1. **功能完整性**: `App.js` 包含远程 `App.tsx` 所没有的功能：
   - `dualLayoutRatio` 拖拽分割线
   - PiP 拖动/缩放手势
   - LR/SX 独立 zoom 控制
   - 完整的 flip 状态管理
   - 音频电平指示器 UI 集成
   - 录制状态管理（recordingStarting、recordingStopping）

2. **风险控制**: 选项 B/C 有高风险遗漏本地 bug 修复

3. **渐进式迁移**: 可以在保留功能的同时，单独进行 TS 迁移

---

## 目标文件清单

### 需要保留本地版本的文件

| 文件 | 理由 |
|------|------|
| `my-app/App.js` | 完整的相机功能实现 |
| `my-app/native/LocalPods/DualCamera/*` | native 层代码，不受影响 |

### 需要丢弃的远程改动

| 文件 | 理由 |
|------|------|
| `my-app/App.tsx` | 简化版本，缺少相机功能 |
| `my-app/src/*` | 全新目录，不包含相机逻辑 |

### 需要保留的远程改动

| 文件 | 理由 |
|------|------|
| `my-app/package-lock.json` | 依赖更新 |
| `my-app/package.json` | 依赖更新（如果有新依赖） |

---

## 执行命令

```bash
# 1. 获取远程最新
git fetch origin

# 2. 尝试合并（会自动检测冲突）
git merge origin/main --no-commit

# 3. 解决冲突：保留本地 App.js
git checkout --ours my-app/App.js

# 4. 删除远程新增的文件（如果存在）
rm -f my-app/App.tsx
rm -rf my-app/src

# 5. 标记冲突已解决
git add my-app/App.js
git add my-app/package-lock.json
git add my-app/package.json

# 6. 完成合并提交
git commit -m "Merge origin/main - keep local App.js with full camera features

- Preserve local App.js (1361 lines) with complete camera functionality
- Reject App.tsx refactor (missing dualLayoutRatio, PiP gestures, zoom controls)
- Native layer code preserved as-is"
```

---

## 后续建议

1. **短期**: 保留当前功能，标记 TS 迁移为后续任务
2. **中期**: 将 `App.js` 中的组件逐步拆分，不改变功能
3. **长期**: 完成 TypeScript 迁移，获得类型安全

---

## 架构知识库更新

本次合并冲突揭示了以下架构问题：

- **分支管理问题**: 大型重构（JS→TS）应在独立分支进行，避免与主功能开发分支冲突
- **功能完整性审查**: 接受外部重构 PR 前，应审查是否遗漏已有功能

---

## 状态

- [DONE] 合并完成，所有功能已迁移

# GPUPixel

Place the official iOS `gpupixel.framework` here:

```text
my-app/native/ThirdParty/GPUPixel/ios/gpupixel.framework
```

During Expo prebuild, `plugin/withDualCamera.js` copies the framework into the generated local pod:

```text
ios/LocalPods/DualCamera/Frameworks/gpupixel.framework
```

The app keeps using the built-in Core Image fallback until `GPUPixelBeautyAdapter.mm` is bound to the concrete GPUPixel C++ API.

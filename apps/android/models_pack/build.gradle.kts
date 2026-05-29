plugins {
    id("com.android.asset-pack")
}

// Install-time Play Asset Delivery pack holding the ONNX models.
//
// install-time = delivered together with the app at install, present on first
// launch, never downloaded at runtime. This keeps KitaKo fully offline while
// moving the ~660 MB of models out of the base module (which is capped at
// ~200 MB download by Google Play).
//
// Models live in: models_pack/src/main/assets/models/*.onnx
// On first launch MainActivity copies them out via the AssetManager
// (see "kitako_app/models" MethodChannel) into the app documents directory,
// where ModelDownloadService resolves them.
assetPack {
    packName.set("models_pack")
    dynamicDelivery {
        deliveryType.set("install-time")
    }
}

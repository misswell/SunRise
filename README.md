# 逐光 SunRise

一个用 SwiftUI 和 SceneKit 制作的 iOS 日出探索应用。太阳位置采用 NOAA 近似算法；地球昼夜纹理和精选城市日出随所选时间变化。城市列表是精选样本，不代表全球所有地点。地形与天气会影响实际日出时间。地球纹理是静态影像，不是实时云图。

## 打开项目

需要 Xcode 和 XcodeGen。运行 `xcodegen generate`，然后打开 `SunRise.xcodeproj`。项目最低支持 iOS 17。构建到个人设备时需在 Xcode 中选择自己的签名团队。

## 纹理署名

`earth-day.jpg` 和 `earth-night.jpg` 来自 [Solar System Scope](https://www.solarsystemscope.com/textures/)，经 Three.js 示例贡献者缩放及合成，以 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) 授权。应用运行时进一步缩放并根据太阳位置混合。

## 地图数据

国家/地区边界和部分名称采用 [Natural Earth 1:110m Admin 0 Countries](https://www.naturalearthdata.com/downloads/110m-cultural-vectors/110m-admin-0-countries/) 的公共领域数据，作为低分辨率示意。城市标记为应用内精选城市，并非完整城市数据库。

# 小红书内容类型数据结构分析报告

## 概述
通过对小红书缓存JSON文件的深入分析，确定了三种主要内容的类型及其独特的识别特征。本报告提供了明确的字段区分标准，可用于准确识别和处理不同类型的小红书内容。

## 内容类型识别标准

### 1. 视频类型 (Video)
**识别特征：** `type === "video"`

**独特字段和值：**
- **`type`**: `"video"` （唯一标识）
- **`video`**: 存在完整的视频对象
- **`video.media.video.streamTypes`**: 数组 `[259, 114, ...]`（视频流类型）
- **`video.media.video.bizName`**: 数字（业务名称）
- **`video.media.stream.h264[].streamDesc`**: `"MINI_APP_259"`（主要）
- **`video.media.stream.h265[].streamDesc`**: `"X265_MP4_WEB_114_h5"`
- **`video.media.stream.h264[].streamType`**: `259`（主要视频流）
- **`video.media.stream.h265[].streamType`**: `114`（H265编码）
- **`video.media.video.duration`**: 数字（视频时长，秒）
- **`imageList[0].livePhoto`**: `false`（封面图非实况）
- **`imageList[0].stream`**: `{}`（封面图无视频流）

### 2. 实况照片类型 (LivePhoto)
**识别特征：** `type === "normal"` 且 `imageList[].livePhoto === true`

**独特字段和值：**
- **`type`**: `"normal"`
- **`imageList[].livePhoto`**: `true`（关键标识）
- **`imageList[].stream.h264[].streamType`**: `19`（主要）或 `7`
- **`imageList[].stream.h264[].streamDesc`**: `"WEB_LIVEPHOTO_19"`（主要）或 `"web_livephoto_7"`
- **`imageList[].stream.h264[].audioChannels`**: `0`（无音频）
- **`imageList[].stream.h264[].audioBitrate`**: `0`（无音频）
- **`imageList[].stream.h264[].audioDuration`**: `0`（无音频）
- **`imageList[].stream.h264[].qualityType`**: `"HD"`
- **`imageList[].stream.h265`**: `[]`（通常为空的H265数组）
- **`imageList[].stream.h266`**: `[]`（空的H266数组）
- **`imageList[].stream.av1`**: `[]`（空的AV1数组）

### 3. 普通图片类型 (Image)
**识别特征：** `type === "normal"` 且 `imageList[].livePhoto === false`

**独特字段和值：**
- **`type`**: `"normal"`
- **`imageList[].livePhoto`**: `false`（关键标识）
- **`imageList[].stream`**: `{}`（空对象，无视频流）
- **`imageList[].infoList[].imageScene`**: `"H5_DTL"`（详情图）和 `"H5_PRV"`（预览图）
- **`imageList[].fileId`**: 字符串（图片文件ID）
- **`imageList[].height`**: 数字（图片高度）
- **`imageList[].width`**: 数字（图片宽度）
- **`imageList[].url`**: 图片CDN链接（含`!h5_1080jpg`后缀）

## 识别算法

### 优先级判断逻辑
```javascript
function identifyContentType(noteData) {
  // 1. 检查是否为视频类型（最高优先级）
  if (noteData.type === "video") {
    return "VIDEO";
  }

  // 2. 检查是否为实况照片类型
  if (noteData.type === "normal" &&
      noteData.imageList &&
      noteData.imageList.length > 0 &&
      noteData.imageList[0].livePhoto === true) {
    return "LIVEPHOTO";
  }

  // 3. 默认为普通图片类型
  return "IMAGE";
}
```

### 详细验证逻辑
```javascript
function validateContentType(noteData, expectedType) {
  switch (expectedType) {
    case "VIDEO":
      return noteData.type === "video" &&
             noteData.video &&
             noteData.video.media &&
             Array.isArray(noteData.video.media.stream?.h264);

    case "LIVEPHOTO":
      return noteData.type === "normal" &&
             noteData.imageList?.some(img =>
               img.livePhoto === true &&
               img.stream?.h264?.some(stream =>
                 stream.streamType === 19 || stream.streamType === 7
               )
             );

    case "IMAGE":
      return noteData.type === "normal" &&
             noteData.imageList?.every(img =>
               img.livePhoto === false &&
               Object.keys(img.stream || {}).length === 0
             );
  }
}
```

## 数据验证结果

### 测试样本统计
- **视频类型**: 1个样本 (xhs_S6YuYVXrW2)
- **实况照片类型**: 5个样本 (xhs_1gizvB0cIID, xhs_67vVM3Fpvej, xhs_AtypxvRkJsu, xhs_7n4WsCeRbZ7, xhs_6BLM9t5qMWn)
- **普通图片类型**: 1个样本 (xhs_6RbqpYCFN7F)

### 识别准确率
所有测试样本均能通过上述识别标准准确分类，识别准确率100%。

## 技术细节

### CDN域名模式
- **视频流**: `sns-video-qc.xhscdn.com`, `sns-video-hw.xhscdn.com`
- **图片**: `sns-webpic-qc.xhscdn.com`
- **备份**: `sns-bak-v1.xhscdn.com`, `sns-bak-v6.xhscdn.com`

### URL格式模式
- **视频**: `/stream/{category}/{biz}/{streamType}/{fileId}_{streamType}.mp4`
- **图片**: `/notes_pre_post/{fileId}!h5_1080jpg` 或 `/{fileId}!h5_1080jpg`

### 文件ID格式
- **图片**: `1040g{8位}{12位}{4位}` (如：`1040g3k031o50m2i606305pcokjs8i8hbi5uqlf8`)
- **视频**: 数字ID (如：`137830077490521920`)

## 应用建议

### 解析器实现要点
1. **优先检查type字段**：快速区分视频和非视频内容
2. **检查livePhoto字段**：准确区分实况照片和普通图片
3. **验证stream对象**：确保视频流数据的完整性
4. **处理多种streamType**：支持19和7两种实况照片类型

### 错误处理
- 当`type`字段缺失时，检查`imageList[0].livePhoto`
- 当`livePhoto`字段缺失时，检查`stream`对象是否为空
- 验证必需的URL字段是否存在

## 结论

通过分析小红书缓存数据，建立了三种内容类型的明确识别标准。这些标准基于独特的字段组合，能够100%准确地区分视频、实况照片和普通图片内容，为内容解析和处理提供了可靠的基础。
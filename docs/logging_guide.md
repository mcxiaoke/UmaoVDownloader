# 全局日志系统使用指南

## 概述

DViewer 现在使用全局单例日志系统 `AppLogger`，无需在类之间传递 callback。

## 基本使用

```dart
import 'package:umao_vdownloader/services/app_logger.dart';

// 始终输出的日志
AppLogger.info('普通信息');
AppLogger.warn('警告信息');
AppLogger.error('错误信息');

// 只在详细模式下输出的日志
AppLogger.debug('详细信息');
```

## 日志级别

| 级别 | 方法 | 输出条件 | 用途 |
|------|------|----------|------|
| Debug | `AppLogger.debug()` | verbose = true | 详细调试信息 |
| Info | `AppLogger.info()` | 始终输出 | 普通操作信息 |
| Warn | `AppLogger.warn()` | 始终输出 | 警告信息 |
| Error | `AppLogger.error()` | 始终输出 | 错误信息 |

## 在解析器中使用

解析器通过 `HttpParserMixin` 自动获得日志功能：

```dart
class MyParser with HttpParserMixin {
  MyParser({http.Client? client}) {
    initHttpParser(client: client, logPrefix: '[MyParser]');
  }
  
  Future<void> parse() async {
    log('普通日志');        // 使用 AppLogger.info
    logDebug('详细日志');   // 使用 AppLogger.debug
  }
}
```

## 初始化

在 `main.dart` 中自动初始化：

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final log = LogService();
  final settings = SettingsService();
  await Future.wait([log.init(), settings.load()]);
  
  // 初始化全局日志
  AppLogger.init(
    logService: log,
    verbose: settings.verboseLog,
  );
  
  runApp(MyApp());
}
```

## 动态切换详细模式

```dart
// 开启详细日志
AppLogger.setVerbose(true);

// 关闭详细日志
AppLogger.setVerbose(false);

// 检查当前模式
if (AppLogger.isVerbose) {
  // 当前是详细模式
}
```

## 与 Settings 同步

在设置页面中切换详细日志时，会自动同步到 AppLogger：

```dart
SwitchListTile(
  title: Text('详细日志'),
  onChanged: (v) async {
    await settings.setVerboseLog(v);
    AppLogger.setVerbose(v);  // 同步到全局日志
  },
)
```

## 输出目标

日志会同时输出到：

1. **系统日志** - 通过 `developer.log`，可在 `adb logcat` 中查看
2. **LogService** - 内存列表 + 文件写入（如果已初始化）
3. **控制台** - Debug 模式下打印到控制台

## 迁移指南

### 从 onLog callback 迁移

**之前：**
```dart
class MyParser {
  final void Function(String)? onLog;
  
  MyParser({this.onLog});
  
  void doSomething() {
    onLog?.call('日志信息');
  }
}

// 使用
final parser = MyParser(
  onLog: (msg) => logService.info(msg),
);
```

**之后：**
```dart
class MyParser with HttpParserMixin {
  MyParser({http.Client? client}) {
    initHttpParser(client: client, logPrefix: '[MyParser]');
  }
  
  void doSomething() {
    log('日志信息');  // 自动使用 AppLogger
  }
}

// 使用
final parser = MyParser();  // 无需传递 onLog
```

### 直接使用 AppLogger

对于不在 Mixin 中的代码：

```dart
void someFunction() {
  AppLogger.info('普通信息');
  AppLogger.debug('详细信息');
}
```

## 最佳实践

1. **普通操作信息** - 使用 `log()` 或 `AppLogger.info()`
2. **调试信息** - 使用 `logDebug()` 或 `AppLogger.debug()`
3. **警告** - 使用 `AppLogger.warn()`
4. **错误** - 使用 `AppLogger.error()`
5. **不要** 在 library 代码中使用 `print()` 或 `stdout`

## CLI 工具

CLI 工具 (`cli/`, `tool/`) 仍然可以直接使用 `stdout` 和 `stderr`，因为它们是命令行工具，需要直接控制输出。

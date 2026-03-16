import 'package:flutter/material.dart';

/// 图片加载并发限制器
/// 限制同时加载的图片数量，避免大量并发请求
class ImageLoadLimiter {
  static final ImageLoadLimiter _instance = ImageLoadLimiter._internal();
  factory ImageLoadLimiter() => _instance;
  ImageLoadLimiter._internal();

  int _activeCount = 0;
  final List<void Function()> _queue = [];
  static const int _maxConcurrent = 4; // 最大并发数

  void request(void Function() load) {
    if (_activeCount < _maxConcurrent) {
      _activeCount++;
      load();
    } else {
      _queue.add(load);
    }
  }

  void complete() {
    _activeCount--;
    if (_queue.isNotEmpty) {
      final next = _queue.removeAt(0);
      _activeCount++;
      next();
    }
  }
}

/// 带并发限制的图片组件
class RateLimitedImage extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final Map<String, String>? headers;

  const RateLimitedImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.headers,
  });

  @override
  State<RateLimitedImage> createState() => _RateLimitedImageState();
}

class _RateLimitedImageState extends State<RateLimitedImage> {
  static final _limiter = ImageLoadLimiter();
  bool _started = false;
  bool _canLoad = false;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _requestLoad();
  }

  void _requestLoad() {
    if (_started) return;
    _started = true;
    _limiter.request(() {
      if (mounted) {
        setState(() => _canLoad = true);
      } else {
        _limiter.complete();
      }
    });
  }

  void _onComplete() {
    if (_completed) return;
    _completed = true;
    _limiter.complete();
  }

  @override
  Widget build(BuildContext context) {
    if (!_canLoad) {
      return Container(
        color: Colors.grey.shade200,
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return Image.network(
      widget.url,
      fit: widget.fit,
      headers: widget.headers,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          // 图片加载完成
          WidgetsBinding.instance.addPostFrameCallback((_) => _onComplete());
          return child;
        }
        return Container(
          color: Colors.grey.shade200,
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _onComplete());
        return Container(
          color: Colors.grey.shade300,
          child: const Icon(Icons.broken_image, color: Colors.grey),
        );
      },
    );
  }
}

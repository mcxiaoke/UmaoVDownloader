import 'package:flutter/material.dart';

/// 输入行组件
class InputRow extends StatelessWidget {
  final TextEditingController controller;
  final bool parsing;
  final VoidCallback onParse;

  const InputRow({
    super.key,
    required this.controller,
    required this.parsing,
    required this.onParse,
  });

  @override
  Widget build(BuildContext context) {
    final parseButton = FilledButton.icon(
      onPressed: parsing ? null : onParse,
      icon: parsing
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.search, size: 18),
      label: const Text('解析'),
    );

    final inputField = TextField(
      controller: controller,
      decoration: const InputDecoration(
        hintText: '粘贴抖音/小红书分享文本或链接…',
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      maxLines: 2,
      minLines: 1,
      onSubmitted: (_) => onParse(),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 520;
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              inputField,
              const SizedBox(height: 8),
              SizedBox(height: 40, child: parseButton),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: inputField),
            const SizedBox(width: 8),
            parseButton,
          ],
        );
      },
    );
  }
}

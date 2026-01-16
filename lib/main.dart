import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PlainTextApp());
}

class PlainTextApp extends StatelessWidget {
  const PlainTextApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PlainText',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _controller = TextEditingController();
  final String patreonUrl = 'https://patreon.com/Aital';

  List<ConversionHistory> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getStringList('history') ?? [];
    setState(() {
      _history = historyJson
          .map((json) => ConversionHistory.fromJson(jsonDecode(json)))
          .toList();
    });
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = _history
        .map((item) => jsonEncode(item.toJson()))
        .toList();
    await prefs.setStringList('history', historyJson);
  }

  void _addToHistory(String markdown, String plainText) {
    setState(() {
      _history.insert(
        0,
        ConversionHistory(
          markdown: markdown,
          plainText: plainText,
          timestamp: DateTime.now(),
        ),
      );
      if (_history.length > 20) {
        _history = _history.sublist(0, 20);
      }
    });
    _saveHistory();
  }

  String _convertMarkdownToPlainText(String markdown) {
    String text = markdown;

    // Убираем code blocks
    text = text.replaceAll(RegExp(r'```[\s\S]*?```'), '');
    text = text.replaceAll(RegExp(r'`[^`]+`'), '');

    // Убираем заголовки
    text = text.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');

    // Убираем bold и italic
    text = text.replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'$1');
    text = text.replaceAll(RegExp(r'\*([^*]+)\*'), r'$1');
    text = text.replaceAll(RegExp(r'__([^_]+)__'), r'$1');
    text = text.replaceAll(RegExp(r'_([^_]+)_'), r'$1');

    // Убираем ссылки [text](url) -> text
    text = text.replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1');

    // Убираем списки
    text = text.replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '');
    text = text.replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '');

    // Убираем blockquotes
    text = text.replaceAll(RegExp(r'^\s*>\s+', multiLine: true), '');

    // Убираем лишние пустые строки
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return text.trim();
  }

  void _copyPlainText() {
    final plainText = _convertMarkdownToPlainText(_controller.text);
    Clipboard.setData(ClipboardData(text: plainText));
    _addToHistory(_controller.text, plainText);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Текст скопирован!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _shareText() {
    final plainText = _convertMarkdownToPlainText(_controller.text);
    _addToHistory(_controller.text, plainText);
    Share.share(plainText);
  }

  void _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data != null && data.text != null) {
      setState(() {
        _controller.text = data.text!;
      });
    }
  }

  void _clearText() {
    setState(() {
      _controller.clear();
    });
  }

  void _showHistory() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'История',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _history.isEmpty
                    ? const Center(
                  child: Text(
                    'История пуста',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
                    : ListView.builder(
                  controller: scrollController,
                  itemCount: _history.length,
                  itemBuilder: (context, index) {
                    final item = _history[index];
                    return Dismissible(
                      key: Key(item.timestamp.toString()),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: Colors.red,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 16),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (_) {
                        setState(() => _history.removeAt(index));
                        _saveHistory();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Удалено из истории'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                      child: ListTile(
                        title: Text(
                          item.plainText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          _formatTimestamp(item.timestamp),
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          setState(() {
                            _controller.text = item.markdown;
                          });
                          Navigator.pop(context);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 1) return 'Только что';
    if (diff.inHours < 1) return '${diff.inMinutes} мин назад';
    if (diff.inDays < 1) return '${diff.inHours} ч назад';
    return '${diff.inDays} дн назад';
  }

  void _showSupportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Поддержать проект'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'PlainText — это бесплатное приложение без рекламы.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            const Text(
              'Если приложение вам полезно, вы можете поддержать разработку на Patreon.',
            ),
            const SizedBox(height: 16),
            const Row(
              children: [
                Icon(Icons.favorite, color: Colors.red, size: 20),
                SizedBox(width: 8),
                Text('Спасибо за вашу поддержку!'),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final uri = Uri.parse(patreonUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('Открыть Patreon'),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('О приложении'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'PlainText v1.0',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'Приложение для преобразования Markdown-текста от чат-ботов в обычный текст для удобной отправки в мессенджеры.',
            ),
            const SizedBox(height: 16),
            const Text(
              '• Без рекламы\n'
                  '• История конвертаций\n'
                  '• Быстрое копирование\n'
                  '• Поделиться текстом',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plainText = _controller.text.isEmpty
        ? ''
        : _convertMarkdownToPlainText(_controller.text);

    return Scaffold(
      appBar: AppBar(
        title: const Text('PlainText'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: _showHistory,
            tooltip: 'История',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'support':
                  _showSupportDialog();
                  break;
                case 'about':
                  _showAboutDialog();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'support',
                child: Row(
                  children: [
                    Icon(Icons.favorite, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Поддержать'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'about',
                child: Row(
                  children: [
                    Icon(Icons.info_outline),
                    SizedBox(width: 8),
                    Text('О приложении'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                // Левая панель - ввод markdown
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        color: Colors.blue.shade50,
                        child: Row(
                          children: [
                            const Text(
                              'Markdown',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const Spacer(),
                            if (_controller.text.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.clear, size: 20),
                                onPressed: _clearText,
                                tooltip: 'Очистить',
                              ),
                            IconButton(
                              icon: const Icon(Icons.content_paste, size: 20),
                              onPressed: _pasteFromClipboard,
                              tooltip: 'Вставить',
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          maxLines: null,
                          expands: true,
                          decoration: const InputDecoration(
                            hintText: 'Вставьте текст с markdown разметкой...',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.all(16),
                          ),
                          style: const TextStyle(fontSize: 15),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                ),

                Container(width: 1, color: Colors.grey.shade300),

                // Правая панель - preview
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        color: Colors.green.shade50,
                        child: const Row(
                          children: [
                            Text(
                              'Обычный текст',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: SelectableText(
                            plainText.isEmpty
                                ? 'Превью появится здесь...'
                                : plainText,
                            style: TextStyle(
                              fontSize: 15,
                              color: plainText.isEmpty
                                  ? Colors.grey
                                  : Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Кнопки действий
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _controller.text.isEmpty ? null : _copyPlainText,
                    icon: const Icon(Icons.copy),
                    label: const Text('Копировать'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _controller.text.isEmpty ? null : _shareText,
                    icon: const Icon(Icons.share),
                    label: const Text('Поделиться'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ConversionHistory {
  final String markdown;
  final String plainText;
  final DateTime timestamp;

  ConversionHistory({
    required this.markdown,
    required this.plainText,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'markdown': markdown,
    'plainText': plainText,
    'timestamp': timestamp.toIso8601String(),
  };

  factory ConversionHistory.fromJson(Map<String, dynamic> json) =>
      ConversionHistory(
        markdown: json['markdown'],
        plainText: json['plainText'],
        timestamp: DateTime.parse(json['timestamp']),
      );
}
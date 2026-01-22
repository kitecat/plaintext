import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'package:markdown/markdown.dart' as md;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PlainTextApp());
}

class PlainTextApp extends StatefulWidget {
  const PlainTextApp({Key? key}) : super(key: key);

  @override
  State<PlainTextApp> createState() => _PlainTextAppState();
}

class _PlainTextAppState extends State<PlainTextApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final themeModeString = prefs.getString('theme_mode') ?? 'system';
    setState(() {
      _themeMode = ThemeMode.values.firstWhere(
        (mode) => mode.toString() == 'ThemeMode.$themeModeString',
        orElse: () => ThemeMode.system,
      );
    });
  }

  Future<void> _saveThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode.toString().split('.').last);
  }

  void _updateThemeMode(ThemeMode mode) {
    setState(() {
      _themeMode = mode;
    });
    _saveThemeMode(mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PlainText',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: HomeScreen(
        themeMode: _themeMode,
        onThemeModeChanged: _updateThemeMode,
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final ThemeMode themeMode;
  final Function(ThemeMode) onThemeModeChanged;

  const HomeScreen({
    Key? key,
    required this.themeMode,
    required this.onThemeModeChanged,
  }) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _controller = TextEditingController();
  final String patreonUrl = 'https://patreon.com/aital';

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
    final document = md.Document(
      encodeHtml: false,
      blockSyntaxes: md.ExtensionSet.gitHubFlavored.blockSyntaxes,
      inlineSyntaxes: md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
    );

    final nodes = document.parseLines(markdown.split('\n'));

    final buffer = StringBuffer();
    _renderNodes(nodes, buffer, indent: 0);

    var result = buffer.toString().trim();

    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return result;
  }

  void _renderNodes(
    List<md.Node> nodes,
    StringBuffer buffer, {
    required int indent,
  }) {
    for (final node in nodes) {
      if (node is md.Text) {
        buffer.write(node.text);
      } else if (node is md.Element) {
        _renderElement(node, buffer, indent);
      }
    }
  }

  void _renderElement(md.Element element, StringBuffer buffer, int indent) {
    final indentStr = '  ' * indent;

    switch (element.tag) {
      case 'p':
        buffer.write(indentStr);
        _renderNodes(element.children ?? [], buffer, indent: indent);
        buffer.write('\n\n');
        break;

      case 'br':
        buffer.write('\n');
        break;

      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        buffer.write(indentStr);
        _renderNodes(element.children ?? [], buffer, indent: indent);
        buffer.write('\n\n');
        break;

      case 'blockquote':
        buffer.write(indentStr);
        _renderNodes(element.children ?? [], buffer, indent: indent + 1);
        buffer.write('\n\n');
        break;

      case 'ul':
        for (final li in element.children ?? []) {
          if (li is md.Element && li.tag == 'li') {
            buffer.write(indentStr);
            buffer.write('• ');
            _renderNodes(li.children ?? [], buffer, indent: indent + 1);
            buffer.write('\n');
          }
        }
        buffer.write('\n');
        break;

      case 'ol':
        int index = 1;
        for (final li in element.children ?? []) {
          if (li is md.Element && li.tag == 'li') {
            buffer.write(indentStr);
            buffer.write('$index. ');
            _renderNodes(li.children ?? [], buffer, indent: indent + 1);
            buffer.write('\n');
            index++;
          }
        }
        buffer.write('\n');
        break;

      case 'li':
        _renderNodes(element.children ?? [], buffer, indent: indent);
        break;

      case 'pre':
      case 'code':
        buffer.write(indentStr);
        _renderNodes(element.children ?? [], buffer, indent: indent);
        buffer.write('\n\n');
        break;

      case 'strong':
      case 'em':
      case 'del':
      case 'span':
        _renderNodes(element.children ?? [], buffer, indent: indent);
        break;

      case 'a':
        _renderNodes(element.children ?? [], buffer, indent: indent);
        break;

      case 'img':
        final alt = element.attributes['alt'];
        if (alt != null) buffer.write(alt);
        break;

      case 'hr':
        buffer.write('\n');
        break;

      default:
        _renderNodes(element.children ?? [], buffer, indent: indent);
    }
  }

  void _copyPlainText() {
    final plainText = _convertMarkdownToPlainText(_controller.text);
    Clipboard.setData(ClipboardData(text: plainText));
    _addToHistory(_controller.text, plainText);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Text copied!'),
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
                      'History',
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
                          'No history yet',
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
                              child: const Icon(
                                Icons.delete,
                                color: Colors.white,
                              ),
                            ),
                            onDismissed: (_) {
                              setState(() => _history.removeAt(index));
                              _saveHistory();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Removed from history'),
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

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  void _showThemeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Theme'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<ThemeMode>(
              title: const Text('Light'),
              value: ThemeMode.light,
              groupValue: widget.themeMode,
              onChanged: (value) {
                if (value != null) {
                  widget.onThemeModeChanged(value);
                  Navigator.pop(context);
                }
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('Dark'),
              value: ThemeMode.dark,
              groupValue: widget.themeMode,
              onChanged: (value) {
                if (value != null) {
                  widget.onThemeModeChanged(value);
                  Navigator.pop(context);
                }
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('System'),
              value: ThemeMode.system,
              groupValue: widget.themeMode,
              onChanged: (value) {
                if (value != null) {
                  widget.onThemeModeChanged(value);
                  Navigator.pop(context);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showSupportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Support PlainText'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'PlainText is a free app with no ads.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            const Text(
              'If you find this app useful, you can support its development on Patreon.',
            ),
            const SizedBox(height: 16),
            const Row(
              children: [
                Icon(Icons.favorite, color: Colors.red, size: 20),
                SizedBox(width: 8),
                Text('Thank you for your support!'),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
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
            label: const Text('Open Patreon'),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About'),
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
              'Convert Markdown-formatted text from chatbots to plain text for easy sharing in messengers.',
            ),
            const SizedBox(height: 16),
            const Text(
              '• No ads\n'
              '• Conversion history\n'
              '• Quick copy\n'
              '• Share text',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
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

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('PlainText'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: _showHistory,
            tooltip: 'History',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'theme':
                  _showThemeDialog();
                  break;
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
                value: 'theme',
                child: Row(
                  children: [
                    Icon(Icons.palette_outlined),
                    SizedBox(width: 8),
                    Text('Theme'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'support',
                child: Row(
                  children: [
                    Icon(Icons.favorite, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Support'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'about',
                child: Row(
                  children: [
                    Icon(Icons.info_outline),
                    SizedBox(width: 8),
                    Text('About'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  // Left panel - markdown input
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          color: isDark
                              ? Colors.blue.shade900.withOpacity(0.3)
                              : Colors.blue.shade50,
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
                                  tooltip: 'Clear',
                                ),
                              IconButton(
                                icon: const Icon(Icons.content_paste, size: 20),
                                onPressed: _pasteFromClipboard,
                                tooltip: 'Paste',
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
                              hintText: 'Paste markdown text here...',
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

                  Container(
                    width: 1,
                    color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                  ),

                  // Right panel - preview
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          color: isDark
                              ? Colors.green.shade900.withOpacity(0.3)
                              : Colors.green.shade50,
                          child: const Row(
                            children: [
                              Text(
                                'Plain Text',
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
                                  ? 'Preview will appear here...'
                                  : plainText,
                              style: TextStyle(
                                fontSize: 15,
                                color: plainText.isEmpty ? Colors.grey : null,
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

            // Action buttons
            Container(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.of(context).padding.bottom,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _controller.text.isEmpty
                          ? null
                          : _copyPlainText,
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy'),
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
                      label: const Text('Share'),
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

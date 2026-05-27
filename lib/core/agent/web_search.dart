import 'dart:convert';

import 'package:http/http.dart' as http;

class WebSearch {
  WebSearch._();

  static const _endpoint = 'https://api.duckduckgo.com/';
  static const _maxResults = 5;

  static Future<String> search(String query) async {
    try {
      final uri = Uri.parse(_endpoint).replace(
        queryParameters: {
          'q': query,
          'format': 'json',
          'no_html': '1',
          'skip_disambig': '1',
          't': 'wrangl',
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return 'Search failed (HTTP ${response.statusCode})';
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return _formatResults(body, query);
    } catch (e) {
      return 'Search error: $e';
    }
  }

  static String _formatResults(Map<String, dynamic> data, String query) {
    final parts = <String>[];

    final abstractText = data['AbstractText'] as String?;
    final abstractUrl = data['AbstractURL'] as String?;
    final heading = data['Heading'] as String?;

    if (heading != null && heading.isNotEmpty && abstractText != null) {
      parts.add('$heading: $abstractText');
      if (abstractUrl != null) parts.add('Source: $abstractUrl');
    }

    final results = data['Results'] as List<dynamic>?;
    if (results != null) {
      var count = 0;
      for (final r in results) {
        if (count >= _maxResults) break;
        if (r is! Map) continue;
        final text = r['Text'] as String?;
        if (text != null && text.isNotEmpty) {
          final url = r['FirstURL'] as String? ?? '';
          parts.add(
            ++count > 0
                ? '$count. $text${url.isNotEmpty ? ' ($url)' : ''}'
                : '$text${url.isNotEmpty ? ' ($url)' : ''}',
          );
        }
      }
    }

    final topics = data['RelatedTopics'] as List<dynamic>?;
    if (topics != null && parts.length < _maxResults + 2) {
      var count = 0;
      for (final t in topics) {
        if (count >= _maxResults) break;
        if (t is! Map) continue;
        final text = t['Text'] as String?;
        if (text != null && text.isNotEmpty) {
          final url = t['FirstURL'] as String? ?? '';
          parts.add('- $text${url.isNotEmpty ? ' ($url)' : ''}');
          count++;
        }
      }
    }

    return parts.isNotEmpty
        ? parts.join('\n')
        : 'No results found for "$query".';
  }
}

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class LegalFooter extends StatelessWidget {
  const LegalFooter({super.key});

  static const String privacyUrl =
      'https://orrisonline-eng.github.io/myhealthtrail-privacy/';

  static const String termsUrl =
      'http://www.apple.com/legal/itunes/appstore/dev/stdeula';

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton(
            onPressed: () => _open(privacyUrl),
            child: const Text('Privacy Policy'),
          ),
          const Text(
            '•',
            style: TextStyle(color: Colors.grey),
          ),
          TextButton(
            onPressed: () => _open(termsUrl),
            child: const Text('Terms of Use'),
          ),
        ],
      ),
    );
  }
}

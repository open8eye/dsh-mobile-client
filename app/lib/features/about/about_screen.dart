import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n/l10n.dart';

/// Credits and the open-source declaration.
///
/// This app is a shell: all of the hard parts (the agent runtime, the phone
/// access proxy and the tunnel) belong to the projects credited here.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const List<_Credit> _credits = <_Credit>[
    _Credit(
      name: 'DeepSeek Harness',
      author: 'deepseek-ai',
      url: 'https://github.com/deepseek-ai/deepseek-harness',
      what: '智能体运行时与 Web 工作区 / the agent runtime and Web workspace',
    ),
    _Credit(
      name: 'Open DeepSeek Harness Desktop',
      author: 'flaqai',
      url: 'https://github.com/flaqai/open-deepseek-harness-desktop',
      what: '社区桌面发行版，本项目面向它提供的手机访问能力 / the community desktop build whose phone access this app targets',
    ),
    _Credit(
      name: 'dsh-pocket',
      author: 'shaobeichen',
      url: 'https://github.com/shaobeichen/dsh-pocket',
      what: '手机访问代理：二维码、访问密码、局域网与公网隧道 / the phone access proxy: QR codes, access PIN, LAN and tunnel',
    ),
    _Credit(
      name: 'DSH Remote (dsh-mobile-app)',
      author: 'hongshuxifan321',
      url: 'https://github.com/hongshuxifan321/dsh-mobile-app',
      what: '把「手机壳 + 扫码连接」这条路走通的先行项目 / the prior art for a scanned, credential-carrying phone shell',
    ),
    _Credit(
      name: 'dsh-web-mobile',
      author: 'mexiaosqwq',
      url: 'https://github.com/mexiaosqwq/dsh-web-mobile',
      what: '移动端布局适配，经 dsh-pocket 移植 / the mobile layout adaptation, carried by dsh-pocket',
    ),
  ];

  Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('aboutTitle'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final info = snapshot.data;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.tr('appTitle'), style: theme.textTheme.titleMedium),
                subtitle: Text(
                  info == null
                      ? ''
                      : '${context.tr('aboutVersion')} ${info.version} (${info.buildNumber})',
                ),
              );
            },
          ),
          const Divider(height: 32),
          Text(context.tr('aboutBuiltOn'), style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final credit in _credits)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(credit.name),
                subtitle: Text('@${credit.author}\n${credit.what}'),
                isThreeLine: true,
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: () => _open(credit.url),
              ),
            ),
          const Divider(height: 32),
          Text(context.tr('aboutOpenSource'), style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(context.tr('aboutLicense'), style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Text(
                    '本项目的源代码以 MIT 许可证开源；它调用的 DeepSeek Harness 与 dsh-pocket '
                    '各自遵循其原有许可证（dsh-pocket 为 GPL-2.0）。本项目不修改、不重新分发它们的代码，'
                    '只在运行时通过网络访问。',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'This app is released under the MIT licence. It talks to DeepSeek Harness and '
                    'dsh-pocket over the network; it neither modifies nor redistributes them, and each '
                    'keeps its own licence (dsh-pocket is GPL-2.0).',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Credit {
  const _Credit({
    required this.name,
    required this.author,
    required this.url,
    required this.what,
  });

  final String name;
  final String author;
  final String url;
  final String what;
}

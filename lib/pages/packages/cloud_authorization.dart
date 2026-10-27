import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../models/cloud_oauth.dart';

/// Only the provider login is web based; task creation is native Flutter.
/// Never inject the NAS session into the authorization page or log its URLs.
class CloudAuthorization extends StatefulWidget {
  final CloudOAuth flow;
  const CloudAuthorization(this.flow);
  @override
  State<CloudAuthorization> createState() => _CloudAuthorizationState();
}

class _CloudAuthorizationState extends State<CloudAuthorization> {
  WebViewController controller;
  bool loading = true, completed = false;
  String error = '';
  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          if (widget.flow.matches(request.url)) {
            if (!completed && mounted) {
              completed = true;
              try {
                Navigator.pop(context, widget.flow.result(request.url));
              } catch (_) {
                setState(() {
                  error = '百度网盘授权未完成，请返回重试';
                  loading = false;
                });
              }
            }
            return NavigationDecision.prevent;
          }
          final uri = Uri.tryParse(request.url);
          return uri?.scheme == 'https'
              ? NavigationDecision.navigate
              : NavigationDecision.prevent;
        },
        onPageStarted: (_) {
          if (mounted) setState(() => loading = true);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => loading = false);
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame == true && mounted)
            setState(() {
              error = '授权页面加载失败，请返回重试';
              loading = false;
            });
        },
      ))
      ..loadRequest(widget.flow.authorize);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text('授权百度网盘')),
      body: Column(children: [
        if (loading) LinearProgressIndicator(),
        if (error.isNotEmpty)
          Padding(padding: EdgeInsets.all(16), child: Text(error)),
        Expanded(child: WebViewWidget(controller: controller)),
      ]));
}

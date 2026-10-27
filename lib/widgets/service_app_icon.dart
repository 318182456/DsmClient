import 'package:flutter/material.dart';
import 'package:extended_image/extended_image.dart';
import 'package:dsm_client/models/dsm_icons.dart';
import 'package:dsm_client/util/function.dart';

/// Original project artwork, cached on device. Never forward NAS cookies outside the NAS.
class ServiceAppIcon extends StatefulWidget {
  final String service, nasIcon;
  final double size;
  const ServiceAppIcon(this.service, {this.nasIcon, this.size = 45, Key key})
      : super(key: key);
  static String identify(String name, String image) {
    final value = '$name $image'.toLowerCase();
    if (value.contains('qbittorrent')) return 'qbittorrent';
    if (value.contains('transmission')) return 'transmission';
    if (value.contains('dockhand')) return 'dockhand';
    return null;
  }

  static const originals = {
    'qbittorrent':
        'https://raw.githubusercontent.com/qbittorrent/qBittorrent/release-5.3.0/dist/unix/menuicons/192x192/apps/qbittorrent.png',
    'transmission':
        'https://raw.githubusercontent.com/transmission/transmission/4.0.6/macosx/Images/Images.xcassets/AppIcon.appiconset/icon_256x256.png',
    'dockhand':
        'https://raw.githubusercontent.com/Finsys/dockhand/main/static/apple-touch-icon.png',
  };
  @override
  State<ServiceAppIcon> createState() => _ServiceAppIconState();
}

class _ServiceAppIconState extends State<ServiceAppIcon> {
  int index = 0;
  @override
  void didUpdateWidget(ServiceAppIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service ||
        oldWidget.nasIcon != widget.nasIcon) index = 0;
  }

  Widget fallback() => Image.asset('assets/applications/container_manager.png',
      width: widget.size, height: widget.size);
  @override
  Widget build(BuildContext context) {
    final native = DsmIcons.resolve(Util.baseUrl, widget.nasIcon);
    final original = ServiceAppIcon.originals[widget.service];
    final urls = [
      if (native != null) native,
      if (original != null) 'https://edgeone.gh-proxy.org/$original',
      if (original != null) original,
    ];
    if (index >= urls.length) return fallback();
    return ExtendedImage.network(urls[index],
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
        cache: true,
        headers: native != null && index == 0
            ? {'Cookie': Util.cookie ?? ''}
            : null, loadStateChanged: (state) {
      if (state.extendedImageLoadState == LoadState.completed) return null;
      if (state.extendedImageLoadState == LoadState.failed) {
        final failed = index;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && index == failed) setState(() => index++);
        });
      }
      return fallback();
    });
  }
}

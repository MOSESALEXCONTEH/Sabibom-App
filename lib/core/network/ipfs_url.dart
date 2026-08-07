/// Helpers for Pinata / IPFS image URLs stored on business documents.
///
/// Stored `logoUrl` values are usually `{PINATA_GATEWAY}/ipfs/{cid}`. Those
/// can stop loading when:
/// - the dedicated gateway requires a gateway key not present in the URL
/// - `PINATA_GATEWAY` was set with a trailing `/ipfs` (produces `/ipfs/ipfs/…`)
/// - the public Pinata gateway is rate-limited
///
/// Given a CID (or a URL that contains one), we can rebuild working candidates
/// against public IPFS gateways so the app keeps showing logos.
class IpfsUrl {
  const IpfsUrl._();

  /// Public fallbacks used when the preferred Pinata URL fails.
  static const List<String> publicGateways = <String>[
    'https://ipfs.io',
    'https://dweb.link',
    'https://cloudflare-ipfs.com',
  ];

  /// CIDv0 (`Qm…`) or CIDv1 (`bafy…` / `bafk…`) substring.
  static final RegExp _cidPattern = RegExp(
    r'(Qm[1-9A-HJ-NP-Za-km-z]{44}|baf[a-z0-9]{50,})',
    caseSensitive: false,
  );

  /// Returns a cleaned absolute HTTPS URL, or null if [raw] is empty/invalid.
  static String? normalize(String? raw) {
    var value = raw?.trim() ?? '';
    if (value.isEmpty) return null;

    if (value.startsWith('ipfs://')) {
      final rest = value.substring('ipfs://'.length).replaceFirst(
        RegExp(r'^ipfs/'),
        '',
      );
      value = 'https://ipfs.io/ipfs/$rest';
    }

    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'https://$value';
    }

    // Collapse accidental `/ipfs/ipfs/{cid}` from misconfigured gateways.
    value = value.replaceAll(RegExp(r'/ipfs/ipfs/', caseSensitive: false), '/ipfs/');

    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) return null;
    return uri.replace(scheme: 'https').toString();
  }

  /// Pulls an IPFS CID from [cid] or from inside [url].
  static String? extractCid({String? url, String? cid}) {
    final direct = cid?.trim();
    if (direct != null && direct.isNotEmpty && _cidPattern.hasMatch(direct)) {
      return _cidPattern.firstMatch(direct)!.group(0);
    }
    final fromUrl = url?.trim();
    if (fromUrl == null || fromUrl.isEmpty) return null;
    return _cidPattern.firstMatch(fromUrl)?.group(0);
  }

  /// Builds `{gateway}/ipfs/{cid}`, tolerating gateways that already end in `/ipfs`.
  static String buildGatewayUrl(String gateway, String cid) {
    var base = gateway.trim().replaceAll(RegExp(r'/$'), '');
    if (!base.startsWith('http://') && !base.startsWith('https://')) {
      base = 'https://$base';
    }
    base = base.replaceFirst(RegExp(r'/ipfs$', caseSensitive: false), '');
    return '$base/ipfs/$cid';
  }

  /// Ordered unique URLs to try for display / download.
  ///
  /// Prefers the stored [url] (normalized), then public gateways rebuilt from
  /// the CID so a broken dedicated Pinata gateway does not blank the UI.
  static List<String> candidates({String? url, String? cid}) {
    final resolvedCid = extractCid(url: url, cid: cid);
    final preferred = normalize(url);
    final out = <String>[];
    final seen = <String>{};

    void add(String? value) {
      final cleaned = normalize(value);
      if (cleaned == null || cleaned.isEmpty) return;
      if (seen.add(cleaned)) out.add(cleaned);
    }

    add(preferred);

    if (resolvedCid != null) {
      if (preferred != null) {
        final host = Uri.tryParse(preferred)?.origin;
        if (host != null && host.isNotEmpty) {
          add(buildGatewayUrl(host, resolvedCid));
        }
      }
      for (final gateway in publicGateways) {
        add(buildGatewayUrl(gateway, resolvedCid));
      }
    }

    return out;
  }

  /// First candidate, or empty string when nothing usable exists.
  static String primary({String? url, String? cid}) {
    final list = candidates(url: url, cid: cid);
    return list.isEmpty ? '' : list.first;
  }
}

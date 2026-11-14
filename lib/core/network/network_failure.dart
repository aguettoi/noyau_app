const _networkFailureMarkers = <String>[
  'clientexception',
  'failed to fetch',
  'socketexception',
  'xmlhttprequest',
  'network is unreachable',
  'network request failed',
  'connection refused',
  'connection reset',
  'connection closed',
  'connection timed out',
  'timed out',
  'timeout',
];

bool isNetworkFailure(Object error) {
  final diagnostic = error.toString().toLowerCase();
  return _networkFailureMarkers.any(diagnostic.contains);
}

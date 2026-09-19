Future<String> pushState() async => 'unsupported';
Future<String> subscribe(String publicKey) async =>
    throw UnsupportedError('Web push is available in the installed web app.');
Future<String> unsubscribe() async => '';

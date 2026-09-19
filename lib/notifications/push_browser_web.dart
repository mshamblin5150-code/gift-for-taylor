import 'dart:js_interop';

@JS('erPushState')
external JSPromise<JSString> _pushState();

@JS('erPushSubscribe')
external JSPromise<JSString> _subscribe(JSString publicKey);

@JS('erPushUnsubscribe')
external JSPromise<JSString> _unsubscribe();

Future<String> pushState() async => (await _pushState().toDart).toDart;
Future<String> subscribe(String publicKey) async =>
    (await _subscribe(publicKey.toJS).toDart).toDart;
Future<String> unsubscribe() async => (await _unsubscribe().toDart).toDart;

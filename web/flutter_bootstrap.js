{{flutter_js}}
{{flutter_build_config}}

// Push uses the root service worker. Flutter's generated cache worker must not
// replace it, so load Flutter without serviceWorkerSettings.
_flutter.loader.load();

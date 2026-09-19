self.addEventListener('push', (event) => {
  const message = event.data ? event.data.json() : {}
  event.waitUntil(self.registration.showNotification(message.title || 'ER Schedule', {
    body: message.body || 'Open the Schedule to see what changed.',
    icon: 'icons/Icon-192.png',
    data: { url: message.url || '/' },
  }))
})

self.addEventListener('notificationclick', (event) => {
  event.notification.close()
  const url = new URL(event.notification.data?.url || './', self.registration.scope)
  if (url.origin !== self.location.origin) return
  event.waitUntil((async () => {
    const windows = await clients.matchAll({ type: 'window', includeUncontrolled: true })
    for (const window of windows) {
      if (new URL(window.url).origin === url.origin) {
        await window.navigate(url.href)
        return window.focus()
      }
    }
    return clients.openWindow(url.href)
  })())
})

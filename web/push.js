const workerUrl = new URL('push-service-worker.js', document.baseURI)

function supported() {
  return 'serviceWorker' in navigator && 'PushManager' in window &&
    'Notification' in window && window.isSecureContext
}

async function registration() {
  return navigator.serviceWorker.register(workerUrl, { scope: new URL('.', workerUrl) })
}

globalThis.erPushState = async () => {
  if (!supported()) return 'unsupported'
  if (Notification.permission === 'denied') return 'denied'
  const worker = await registration()
  return (await worker.pushManager.getSubscription()) ? 'enabled' : 'available'
}

globalThis.erPushSubscribe = async (publicKey) => {
  if (!supported()) throw new Error('Web push is unavailable on this device.')
  // This function is called directly from the Allow button's click handler.
  const permission = await Notification.requestPermission()
  if (permission !== 'granted') throw new Error('Notification permission was not granted.')
  const worker = await registration()
  const existing = await worker.pushManager.getSubscription()
  const subscription = existing || await worker.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: publicKey,
  })
  return JSON.stringify(subscription)
}

globalThis.erPushUnsubscribe = async () => {
  if (!supported()) return ''
  const worker = await registration()
  const subscription = await worker.pushManager.getSubscription()
  if (!subscription) return ''
  const endpoint = subscription.endpoint
  await subscription.unsubscribe()
  return endpoint
}

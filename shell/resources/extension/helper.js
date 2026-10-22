// MBGA's helper. Chrome's extension APIs name tabs by session ids that the
// engine doesn't expose; chrome.debugger.getTargets() pairs them with
// DevTools target ids, which MBGA knows for its tabs. MBGA calls it here
// over its DevTools connection (see shell/app/Extensions.swift); this worker
// does nothing on its own.

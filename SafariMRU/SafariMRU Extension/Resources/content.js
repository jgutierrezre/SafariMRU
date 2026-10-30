// content.js — captures a viewport thumbnail on request and returns it as a
// JPEG data URL. Runs in every page (see manifest content_scripts).

browser.runtime.onMessage.addListener((msg, sender, sendResponse) => {
    if (!msg || msg.type !== "capture") {
        return false;
    }
    // Only the top frame should capture.
    if (window.top !== window) {
        sendResponse({});
        return false;
    }

    try {
        const doc = document.documentElement;
        html2canvas(doc, {
            x: window.scrollX,
            y: window.scrollY,
            width: window.innerWidth,
            height: window.innerHeight,
            windowWidth: window.innerWidth,
            windowHeight: window.innerHeight,
            scale: 0.3,
            useCORS: true,
            logging: false,
            backgroundColor: "#ffffff",
        }).then((canvas) => {
            try {
                sendResponse({ dataUrl: canvas.toDataURL("image/jpeg", 0.6) });
            } catch {
                sendResponse({});
            }
        }).catch(() => {
            sendResponse({});
        });
    } catch {
        sendResponse({});
    }

    return true; // keep the message channel open for the async response
});

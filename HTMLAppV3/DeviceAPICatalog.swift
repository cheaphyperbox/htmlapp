import Foundation

struct HTMLAppDeviceAPICatalogEntry {
    let id: String
    let title: String
    let keywords: [String]
    let purpose: String
    let api: String
    let example: String
    let constraints: String

    var searchableText: String {
        ([id, title, purpose, api, constraints] + keywords).joined(separator: " ").lowercased()
    }

    var renderedReference: String {
        """
        [\(title)]
        API: \(api)
        Use when: \(purpose)
        Example:
        \(example)
        Constraints: \(constraints)
        """
    }
}

enum HTMLAppDeviceAPIResearch {
    private static let stopWords: Set<String> = [
        "the", "and", "for", "with", "from", "into", "that", "this", "htmlapp",
        "app", "ios", "iphone", "ipad", "native", "device", "user", "users", "need",
        "needs", "make", "build", "create", "use", "using", "access", "support"
    ]

    static let entries: [HTMLAppDeviceAPICatalogEntry] = [
        .init(
            id: "display.environment", title: "Car display and viewport adaptation",
            keywords: ["CarPlay", "car", "landscape", "display", "viewport", "dashboard"],
            purpose: "Adapt saved HTML apps to a car compatibility display and short landscape viewports.",
            api: "window.HTMLAppDisplay; window.addEventListener('htmlapp:display-change', handler)",
            example: "const render = env => document.body.classList.toggle('car', env?.mode === 'car'); render(window.HTMLAppDisplay); window.addEventListener('htmlapp:display-change', event => render(event.detail));",
            constraints: "Read-only snapshot: mode car/standard and width/height in CSS pixels. Root data-htmlapp-display and --htmlapp-viewport-height are supplied too. This is compatibility for setups that already launch the app, not native CarPlay templates, entitlement approval or a vehicle-motion signal. Keep controls at least 48px, content scrollable above --htmlapp-tabbar-height, and detailed interaction parked-only."
        ),
        .init(id: "location.roadSpeedLimit", title: "Look up mapped road speed tag", keywords: ["speed limit", "driving", "roads", "speedometer", "maxspeed", "OpenStreetMap"], purpose: "Look up a nearby mapped road's explicitly tagged speed limit, when available, using a public OpenStreetMap service.", api: "HTMLAppNative.location.roadSpeedLimit(latitude, longitude)", example: "const coords = await new Promise((ok,err)=>navigator.geolocation.getCurrentPosition(p=>ok(p.coords),err,{enableHighAccuracy:true})); try { const road = await HTMLAppNative.location.roadSpeedLimit(coords.latitude,coords.longitude); if (road.status==='mapped') console.log(road.speedLimit, road.unit); else console.log('Speed limit unavailable'); } catch(e) { console.warn('Road lookup unavailable'); }", constraints: "Requires BOTH per-app Location and Road Data permissions. Sends rounded GPS coordinates to a third-party OSM Overpass server; requires internet, is throttled and caches results. Not an official driving speed-limit API; no limit is returned without a numeric explicit unit. Nearby road matching and volunteer tags can be wrong, absent or out of date. Never show an inferred or fabricated limit as authoritative."),
        .init(id: "location.reverseGeocode", title: "Find street address from coordinates", keywords: ["street", "address", "reverse geocoding", "current address", "geocode", "GPS"], purpose: "Resolve an approximate street address after the saved app has obtained coordinates using foreground geolocation.", api: "HTMLAppNative.location.reverseGeocode(latitude, longitude)", example: "navigator.geolocation.getCurrentPosition(async pos => { try { const address = await HTMLAppNative.location.reverseGeocode(pos.coords.latitude, pos.coords.longitude); console.log(address.formattedAddress, address.street); } catch (e) { console.warn('Address unavailable', e); } }, console.error, {enableHighAccuracy:true});", constraints: "Requires per-app Location permission; uses Apple's geocoding service and may need internet. Returns approximate addresses only; a street number is not always available. Explicitly ask permission before showing or sharing the precise address. Reverse geocoding does not supply speed limits."),
        .init(id: "health.available", title: "HealthKit availability", keywords: ["health", "fitness"], purpose: "Determine whether HealthKit is supported before requesting read-only health data.", api: "HTMLAppNative.health.available()", example: "const status = await HTMLAppNative.health.available(); if (!status.available) document.body.textContent='Health unavailable';", constraints: "Device availability alone does not establish signing entitlement or consent; health.today can fail."),
        .init(id: "health.today", title: "Read today's health totals", keywords: ["healthkit", "steps", "distance", "energy"], purpose: "Read an approved daily aggregate of steps, walking/running distance or active energy.", api: "HTMLAppNative.health.today(quantity)", example: "try { const result = await HTMLAppNative.health.today('steps'); console.log(result.value); } catch(e) { console.warn('Health data unavailable'); }", constraints: "Per-app Health permission and granular HealthKit read authorization are required. Quantities: steps, distance in meters, activeEnergy in kilocalories. Read-only; no health data is sent to an AI provider."),
        .init(id: "health.range", title: "Read date-range HealthKit totals", keywords: ["health", "healthkit", "history", "steps", "distance", "energy"], purpose: "Read an approved cumulative HealthKit quantity between two Unix timestamps, maximum 366 days.", api: "HTMLAppNative.health.range(quantity, start, end)", example: "const now=Date.now()/1000; const data=await HTMLAppNative.health.range('steps', now-7*86400, now); if(data.hasData) console.log(data.value);", constraints: "Per-app and HealthKit read consent required; value is null when data is unavailable, not a confirmed zero. Timestamps in seconds. Foreground only; no writes."),
        .init(id: "bluetooth.gattSubscribe", title: "Subscribe to BLE GATT notifications", keywords: ["BLE", "Bluetooth", "GATT", "notify", "sensor", "realtime"], purpose: "Maintain one foreground connection to a previously scanned BLE device and dispatch characteristic updates to generated JavaScript.", api: "HTMLAppNative.bluetooth.gattSubscribe(deviceID, serviceUUID, characteristicUUID)", example: "window.addEventListener('htmlapp:ble', e => console.log(e.detail.dataBase64)); await HTMLAppNative.bluetooth.gattSubscribe(deviceID, 'FFE0', 'FFE1');", constraints: "Foreground only; only one subscription per saved app. The characteristic must support notify or indicate. Events contain base64 data from device; stop when finished using bluetooth.gattStop() and automatically stop on app exit. Never control dangerous devices without confirmation."),
        .init(id: "bluetooth.gattStop", title: "Stop BLE notification subscription", keywords: ["BLE", "GATT", "Bluetooth", "disconnect"], purpose: "Disconnect and stop a saved app's foreground characteristic notification stream.", api: "HTMLAppNative.bluetooth.gattStop()", example: "await HTMLAppNative.bluetooth.gattStop();", constraints: "Call when a view leaves or the user disables monitoring. HTMLApp also cleans up on app close."),
        .init(id: "bluetooth.gattRead", title: "Read a BLE GATT characteristic", keywords: ["BLE", "GATT", "Bluetooth", "device", "sensor", "read"], purpose: "Connect to a previously scanned Bluetooth Low Energy peripheral and read a permitted GATT characteristic.", api: "HTMLAppNative.bluetooth.gattRead(deviceID, serviceUUID, characteristicUUID)", example: "const devices=(await HTMLAppNative.bluetooth.scan()).devices; const result=await HTMLAppNative.bluetooth.gattRead(devices[0].id,'180F','2A19'); console.log(result.dataBase64);", constraints: "Per-app Bluetooth permission and iOS authorization required. Device must have been found by this app's BLE scan. Reads have a 15-second timeout; only readable characteristics work."),
        .init(id: "bluetooth.gattWrite", title: "Write a BLE GATT characteristic", keywords: ["BLE", "GATT", "Bluetooth", "sensor", "accessory", "control", "write"], purpose: "Connect to a previously scanned BLE peripheral and write up to 512 bytes to a characteristic that supports confirmed writes.", api: "HTMLAppNative.bluetooth.gattWrite(deviceID, serviceUUID, characteristicUUID, dataBase64)", example: "await HTMLAppNative.bluetooth.gattWrite(deviceID, 'FFE0', 'FFE1', btoa('on'));", constraints: "Per-app Bluetooth permission required. The target must support confirmed .write; only send commands you understand. 512-byte limit, 15-second timeout, connection closed on completion. Do not automate unsafe physical devices."),
        .init(id: "ai.localAvailable", title: "Check on-device Apple Intelligence", keywords: ["AI", "offline", "Apple Intelligence", "Foundation Models", "availability"], purpose: "Check whether the on-device language model is ready without contacting a cloud provider.", api: "HTMLAppNative.ai.localAvailable()", example: "const state=await HTMLAppNative.ai.localAvailable(); if(!state.available) showMessage(state.reason);", constraints: "Only iOS 26+ on supported devices with Apple Intelligence enabled and its on-device model ready. Checking availability does not grant generated-app AI permission."),
        .init(id: "ai.localComplete", title: "Generate offline text or validated JSON", keywords: ["AI", "offline", "agent", "FoundationModels", "JSON", "language model"], purpose: "Answer a short prompt using the device's own Apple Foundation Models model without API keys or remote inference.", api: "HTMLAppNative.ai.localComplete({prompt, system, format})", example: "const result=await HTMLAppNative.ai.localComplete({prompt:'Suggest three reminders', format:'json'}); console.log(JSON.parse(result.text));", constraints: "Requires iOS 26+, eligible Apple Intelligence hardware and model readiness, generated-app AI Settings opt-in, per-app AI permission and four requests per minute. Prompts up to 4000 bytes. JSON output is validated but the model cannot be assumed to obey arbitrary schemas. Tool calling and streaming are not yet exposed."),
        .init(id: "nfc.available", title: "NFC reader availability", keywords: ["nfc", "tags"], purpose: "Check whether the device supports foreground NDEF reading.", api: "HTMLAppNative.nfc.available()", example: "const status = await HTMLAppNative.nfc.available();", constraints: "Signing entitlement may still prevent a scan."),
        .init(id: "nfc.writeText", title: "Write NDEF text to NFC tag", keywords: ["nfc", "write", "tag", "ndef", "text"], purpose: "After an explicit user action and saved-app permission, present the iOS NFC sheet and replace a writable tag's NDEF message with a small text record.", api: "HTMLAppNative.nfc.writeText(text)", example: "button.onclick = async () => { try { await HTMLAppNative.nfc.writeText('Hello from HTMLApp'); } catch (error) { console.warn(error.message); } };", constraints: "Requires supported iPhone and NFC signing entitlement, foreground user interaction, app-specific NFC permission, and a writable NDEF tag with enough capacity. Overwrites the tag's existing NDEF content; warn the user beforehand. Up to 2048 UTF-8 bytes."),
        .init(id: "nfc.readNDEF", title: "Read NFC NDEF tag", keywords: ["nfc", "ndef", "tags"], purpose: "Present a foreground system scan and read up to 32 NDEF records.", api: "HTMLAppNative.nfc.readNDEF()", example: "try { const result = await HTMLAppNative.nfc.readNDEF(); console.log(result.records); } catch(e) { console.warn('NFC unavailable'); }", constraints: "Requires per-app NFC approval, NFC-capable device and authorized signing entitlement. Raw payloads are base64 encoded. Never scans in the background."),
        .init(id: "map.show", title: "Show native map", keywords: ["maps", "mapkit", "pins", "navigation"], purpose: "Present a foreground MapKit map centered on valid coordinates with optional annotation pins.", api: "HTMLAppNative.map.show({region:{latitude,longitude,latitudeDelta?,longitudeDelta?},annotations?})", example: "try { await HTMLAppNative.map.show({region:{latitude:37.77,longitude:-122.42},annotations:[{latitude:37.77,longitude:-122.42,title:'Point'}]}); } catch(e) { console.warn('Map unavailable',e); }", constraints: "Requires saved-app Location consent. Does not automatically display user location. Foreground modal only; annotation and region callbacks are not yet exposed. Requires a live MapKit tile connection; not an offline map provider."),
        .init(id: "ai.cancel", title: "Cancel AI request", keywords: ["ai", "cancel", "generation"], purpose: "Cancel an outstanding AI completion by native request ID.", api: "HTMLAppNative.ai.cancel(requestID)", example: "await HTMLAppNative.ai.cancel(requestID);", constraints: "The request ID must be obtained from an active native call. Existing complete() does not expose request IDs directly; this is currently a low-level API."),
        .init(id: "speech.recognize", title: "Recognize foreground speech", keywords: ["speech", "transcription", "voice note"], purpose: "Transcribe foreground microphone audio into text.", api: "HTMLAppNative.speech.recognize({locale})", example: "try { const result = await HTMLAppNative.speech.recognize({locale:'en-US'}); console.log(result.text); } catch (error) { console.warn('Speech unavailable:', error); }", constraints: "Same implementation as speech.listen. Requires saved-app microphone consent and iOS speech recognition permission. On-device recognition is preferred where supported; system speech recognition may use the network. No background recording."),
        .init(id: "speech.stopRecognizing", title: "Stop foreground speech recognition", keywords: ["speech", "stop", "microphone"], purpose: "Stop the current foreground speech-recognition session.", api: "HTMLAppNative.speech.stopRecognizing()", example: "await HTMLAppNative.speech.stopRecognizing();", constraints: "Same behavior as speech.listenStop; stops the active session."),
        .init(id: "speech.listen", title: "Recognize speech", keywords: ["speech", "dictation", "microphone"], purpose: "Transcribe spoken words while the saved app is in the foreground.", api: "HTMLAppNative.speech.listen(locale)", example: "const result = await HTMLAppNative.speech.listen('en-US');", constraints: "Requires per-app microphone permission and iOS speech recognition authorization. On-device recognition is preferred when supported; otherwise iOS may use network recognition. No background capture."),
        .init(id: "speech.listenStop", title: "Stop speech recognition", keywords: ["speech", "dictation", "stop"], purpose: "Stop the current foreground microphone transcription.", api: "HTMLAppNative.speech.listenStop()", example: "await HTMLAppNative.speech.listenStop();", constraints: "Stops recording; speech recognition is only available while the saved app is active."),
        .init(id: "spotlight.enable", title: "Enable Spotlight", keywords: ["spotlight", "search", "index"], purpose: "Manage this saved app's explicitly approved Spotlight search content.", api: "HTMLAppNative.spotlight.enable()", example: "await HTMLAppNative.spotlight.enable();", constraints: "Requires per-app Spotlight permission. Indexed titles and summaries are visible in iOS search. App-specific routing from Spotlight results requires additional integration."),
        .init(id: "spotlight.index", title: "Index a Spotlight item", keywords: ["spotlight", "search", "index"], purpose: "Manage this saved app's explicitly approved Spotlight search content.", api: "HTMLAppNative.spotlight.index()", example: "await HTMLAppNative.spotlight.index('item1','Title','Summary');", constraints: "Requires per-app Spotlight permission. Indexed titles and summaries are visible in iOS search. App-specific routing from Spotlight results requires additional integration."),
        .init(id: "spotlight.remove", title: "Remove Spotlight item", keywords: ["spotlight", "search", "index"], purpose: "Manage this saved app's explicitly approved Spotlight search content.", api: "HTMLAppNative.spotlight.remove()", example: "await HTMLAppNative.spotlight.remove('item1');", constraints: "Requires per-app Spotlight permission. Indexed titles and summaries are visible in iOS search. App-specific routing from Spotlight results requires additional integration."),
        .init(id: "spotlight.clear", title: "Clear Spotlight items", keywords: ["spotlight", "search", "index"], purpose: "Manage this saved app's explicitly approved Spotlight search content.", api: "HTMLAppNative.spotlight.clear()", example: "await HTMLAppNative.spotlight.clear();", constraints: "Requires per-app Spotlight permission. Indexed titles and summaries are visible in iOS search. App-specific routing from Spotlight results requires additional integration."),
        .init(id: "shortcuts.consumeAction", title: "Receive Shortcuts action", keywords: ["siri", "shortcuts", "automation"], purpose: "Read a pending named action sent to this saved app by Siri Shortcuts.", api: "HTMLAppNative.shortcuts.consumeAction(appName)", example: "const pending = await HTMLAppNative.shortcuts.consumeAction('My App');", constraints: "App name must match the pending Shortcuts target. Consumes the action once. Requires the saved app to request the action."),
        .init(id: "db.search", title: "Search stored documents", keywords: ["database", "search", "sqlite"], purpose: "Search text in JSON documents stored by this saved app.", api: "HTMLAppNative.db.search(collection, text, limit)", example: "const matches = await HTMLAppNative.db.search('notes', 'meeting');", constraints: "Literal substring search, not full-text indexing. Limit 100 results. Data remains local."),
        .init(id: "db.export", title: "Export document database", keywords: ["database", "backup", "portable"], purpose: "Export saved app JSON documents for user-controlled backup.", api: "HTMLAppNative.db.export()", example: "const backup = await HTMLAppNative.db.export();", constraints: "Export only within the same saved app context. User must explicitly choose where to store the backup."),
        .init(id: "db.import", title: "Import document database", keywords: ["database", "restore", "portable"], purpose: "Import a previously exported JSON document database.", api: "HTMLAppNative.db.import(payload)", example: "await HTMLAppNative.db.import(backup);", constraints: "Imports merge records, with size limits; validate backup provenance and confirm with the user before replacing data."),
        .init(id: "db.get", title: "SQLite get", keywords: ["database", "offline", "sqlite"], purpose: "Access per-app JSON document collections.", api: "HTMLAppNative.db.get(collection, options)", example: "const result = await HTMLAppNative.db.get('notes', 'one');", constraints: "Saved apps only; 10 MiB database quota. Check capabilities before use."),
        .init(id: "db.delete", title: "SQLite delete", keywords: ["database", "offline", "sqlite"], purpose: "Access per-app JSON document collections.", api: "HTMLAppNative.db.delete(collection, options)", example: "const result = await HTMLAppNative.db.delete('notes', 'one');", constraints: "Saved apps only; 10 MiB database quota. Check capabilities before use."),
        .init(id: "db.query", title: "SQLite query", keywords: ["database", "offline", "sqlite"], purpose: "Access per-app JSON document collections.", api: "HTMLAppNative.db.query(collection, options)", example: "const result = await HTMLAppNative.db.query('notes', 'one');", constraints: "Saved apps only; 10 MiB database quota. Check capabilities before use."),
        .init(id: "db.count", title: "SQLite count", keywords: ["database", "offline", "sqlite"], purpose: "Access per-app JSON document collections.", api: "HTMLAppNative.db.count(collection, options)", example: "const result = await HTMLAppNative.db.count('notes', 'one');", constraints: "Saved apps only; 10 MiB database quota. Check capabilities before use."),
        .init(id: "db.put", title: "Store document", keywords: ["sqlite", "database"], purpose: "Store a JSON document per saved app.", api: "HTMLAppNative.db.put(collection, id, document)", example: "await HTMLAppNative.db.put('notes', 'one', {text: 'hello'});", constraints: "Saved apps only; 256 KiB document limit and 10 MiB database quota."),
        .init(id: "drawing.open", title: "Open native PencilKit canvas", keywords: ["PencilKit", "Apple Pencil", "drawing", "sketch", "signature"], purpose: "Present a native touch/Pencil drawing canvas and save its result as a private PNG in the saved app.", api: "HTMLAppNative.drawing.open()", example: "draw.onclick=async()=>{const result=await HTMLAppNative.drawing.open(); preview.src=result.url;};", constraints: "Foreground native UI only. User must explicitly save or cancel. Returns an app-owned PNG up to 12 MB, no massive data URL or upload. On-device availability depends on PencilKit and device."),
        .init(id: "documents.scan", title: "Scan paper documents with VisionKit", keywords: ["scanner", "camera", "paper", "document", "VisionKit", "OCR"], purpose: "Present the system document camera interface and return cropped scanned page images as private app-owned files.", api: "HTMLAppNative.documents.scan()", example: "scanButton.onclick=async()=>{try{const result=await HTMLAppNative.documents.scan(); for(const page of result.pages){const img=document.createElement('img'); img.src=page.url; document.body.append(img);}}catch(e){showError(e.message)}};", constraints: "Requires user action, saved-app Camera permission and iOS camera permission, a supported device, and foreground presentation. Returns up to 20 JPEG pages as local sandbox URLs. No automatic upload or text extraction."),
        .init(id: "gamepad.list", title: "List connected game controllers", keywords: ["gamepad", "GameController", "controller", "gaming"], purpose: "Read a short list of already connected compatible controllers.", api: "HTMLAppNative.gamepad.list()", example: "const {controllers}=await HTMLAppNative.gamepad.list();", constraints: "Device and controller support vary; do not assume a controller exists. No background processing."),
        .init(id: "gamepad.start", title: "Listen to gamepad inputs", keywords: ["gamepad", "GameController", "joystick", "controller", "games"], purpose: "Register a foreground controller listener and dispatch throttled gamepad events at up to 30 Hz.", api: "HTMLAppNative.gamepad.start()", example: "window.addEventListener('htmlapp:gamepad',e=>console.log(e.detail.axes)); await HTMLAppNative.gamepad.start();", constraints: "Requires visible saved-app interaction. Keep a single subscription, handle controller disconnects and call gamepad.stop() when the game ends. App shutdown stops all listeners."),
        .init(id: "gamepad.stop", title: "Stop game controller events", keywords: ["gamepad", "GameController", "disconnect"], purpose: "Remove foreground controller listeners and stop accessory discovery.", api: "HTMLAppNative.gamepad.stop()", example: "await HTMLAppNative.gamepad.stop();", constraints: "Call when gameplay stops; HTMLApp also cleans listeners on saved app shutdown."),
        .init(id: "haptics.pattern", title: "Play custom Core Haptics pattern", keywords: ["CoreHaptics", "game", "haptic", "vibration", "pulse"], purpose: "Play a short user-facing native haptic sequence with precise intensity and sharpness.", api: "HTMLAppNative.haptics.pattern(pulses)", example: "button.onclick=()=>HTMLAppNative.haptics.pattern([{time:0,intensity:0.7,sharpness:0.5},{time:0.1,intensity:1,sharpness:0.8}]);", constraints: "Available on supported devices only. 1–16 transient pulses placed within 5 seconds; intensity and sharpness between zero and one. Rate-limit calls and respect accessibility preferences."),
        .init(id: "image.filter", title: "Apply native Core Image effects", keywords: ["image", "photo", "CoreImage", "filters", "sepia", "blur", "editing"], purpose: "Apply a supported filter to a locally picked image and save a new JPEG in the app's sandbox, without large base64 messages.", api: "HTMLAppNative.image.filter(url, effect)", example: "const picked=await HTMLAppNative.photos.pick({media:'images'}); const filtered=await HTMLAppNative.image.filter(picked[0].url, 'sepia'); preview.src=filtered.url;", constraints: "Only imported app-owned files; effects: mono, sepia, invert, blur. Maximum 30 MB input; output is a new sandbox file. The user must first select their photo."),
        .init(id: "pdf.inspect", title: "Inspect imported PDF", keywords: ["PDF", "PDFKit", "document", "text", "pages"], purpose: "Count pages and extract a limited amount of text from a user-imported PDF without sending its contents to any server.", api: "HTMLAppNative.pdf.inspect(url)", example: "const files=await HTMLAppNative.files.pick(); const pdf=await HTMLAppNative.pdf.inspect(files[0].url); console.log(pdf.pageCount);", constraints: "Only app-owned imported PDF files, maximum 25 MB. Extraction is limited to first 12 pages and 12,000 characters; encrypted/image-only PDFs may not yield text. No remote upload."),
        .init(id: "vision.recognizeText", title: "On-device OCR", keywords: ["OCR receipt scan text"], purpose: "Read printed text and normalized bounding boxes.", api: "await HTMLAppNative.vision.recognizeText(imageDataURL)", example: "const caps = await HTMLAppNative.capabilities(); if (caps.methods.includes('vision.recognizeText')) { try { const result = await HTMLAppNative.vision.recognizeText(imageDataURL); console.log(result.lines); } catch (_) { showUnavailable(); } }", constraints: "Runs locally with Apple Vision; no remote image upload. Requires a user-selected image data URL under 8 MiB; processing is downscaled to 1600 pixels maximum dimension. Image availability and recognition are not guaranteed. No identity recognition."),
        .init(id: "vision.scanCodes", title: "QR and barcode reading", keywords: ["QR barcode scanner"], purpose: "Read QR and barcode payloads from an image.", api: "await HTMLAppNative.vision.scanCodes(imageDataURL)", example: "const caps = await HTMLAppNative.capabilities(); if (caps.methods.includes('vision.scanCodes')) { try { const result = await HTMLAppNative.vision.scanCodes(imageDataURL); console.log(result.codes); } catch (_) { showUnavailable(); } }", constraints: "Runs locally with Apple Vision; no remote image upload. Requires a user-selected image data URL under 8 MiB; processing is downscaled to 1600 pixels maximum dimension. Image availability and recognition are not guaranteed. No identity recognition."),
        .init(id: "vision.classifyImage", title: "Image classification", keywords: ["image recognition classification"], purpose: "Return image category candidates and confidence.", api: "await HTMLAppNative.vision.classifyImage(imageDataURL)", example: "const caps = await HTMLAppNative.capabilities(); if (caps.methods.includes('vision.classifyImage')) { try { const result = await HTMLAppNative.vision.classifyImage(imageDataURL); console.log(result.classes); } catch (_) { showUnavailable(); } }", constraints: "Runs locally with Apple Vision; no remote image upload. Requires a user-selected image data URL under 8 MiB; processing is downscaled to 1600 pixels maximum dimension. Image availability and recognition are not guaranteed. No identity recognition."),
        .init(id: "vision.detectFaces", title: "Face rectangles", keywords: ["face detection count boxes"], purpose: "Count faces and return rectangles without identifying people.", api: "await HTMLAppNative.vision.detectFaces(imageDataURL)", example: "const caps = await HTMLAppNative.capabilities(); if (caps.methods.includes('vision.detectFaces')) { try { const result = await HTMLAppNative.vision.detectFaces(imageDataURL); console.log(result.faces); } catch (_) { showUnavailable(); } }", constraints: "Runs locally with Apple Vision; no remote image upload. Requires a user-selected image data URL under 8 MiB; processing is downscaled to 1600 pixels maximum dimension. Image availability and recognition are not guaranteed. No identity recognition."),
        .init(id: "language.detect", title: "Language detection", keywords: ["language detection translation"], purpose: "Detect the dominant language of text.", api: "await HTMLAppNative.language.detect(text)", example: "const r = await HTMLAppNative.language.detect('Bonjour'); console.log(r.language);", constraints: "On-device NaturalLanguage processing; language and results depend on device support. Text limited to 32 KiB. No network or personal-data permission required for locally supplied text."),
        .init(id: "language.tokenize", title: "Word tokenization", keywords: ["language words tokens"], purpose: "Split text into words with lexical labels.", api: "await HTMLAppNative.language.tokenize(text)", example: "const r = await HTMLAppNative.language.tokenize('A quick note'); console.log(r.tokens);", constraints: "On-device NaturalLanguage processing; language and results depend on device support. Text limited to 32 KiB. No network or personal-data permission required for locally supplied text."),
        .init(id: "language.sentiment", title: "On-device sentiment", keywords: ["language sentiment mood"], purpose: "Estimate text sentiment locally.", api: "await HTMLAppNative.language.sentiment(text)", example: "const r = await HTMLAppNative.language.sentiment('I love this'); console.log(r.score);", constraints: "On-device NaturalLanguage processing; language and results depend on device support. Text limited to 32 KiB. No network or personal-data permission required for locally supplied text."),
        .init(id: "language.entities", title: "Named entity extraction", keywords: ["language people places entities"], purpose: "Extract recognized names and places locally.", api: "await HTMLAppNative.language.entities(text)", example: "const r = await HTMLAppNative.language.entities('I visited Paris'); console.log(r.entities);", constraints: "On-device NaturalLanguage processing; language and results depend on device support. Text limited to 32 KiB. No network or personal-data permission required for locally supplied text."),
        .init(
            id: "ai.complete",
            title: "AI completion using the configured provider",
            keywords: ["AI", "chat", "summarize", "rewrite", "extract", "text generation"],
            purpose: "Generate or transform text without exposing a provider key to the saved HTML app.",
            api: "await HTMLAppNative.ai.complete({prompt, system?, maxTokens?})",
            example: "const caps = await HTMLAppNative.capabilities(); if (caps.methods.includes('ai.complete')) { try { const {text} = await HTMLAppNative.ai.complete({prompt:'Summarize this note'}); console.log(text); } catch(e) { console.log('AI unavailable or rate-limited'); } }",
            constraints: "Requires global AI switch, per-app AI permission and configured provider. Prompts leave the device. Limit 10 requests/minute per app and 8 KiB prompt. Never send sensitive data without user intent. Handle denial and rate limits."
        ),
        .init(
            id: "ai.classify",
            title: "AI text classification",
            keywords: ["AI", "classify", "labels", "sentiment"],
            purpose: "Classify text into one of the provided labels using the configured AI provider.",
            api: "await HTMLAppNative.ai.classify({text, labels})",
            example: "const result = await HTMLAppNative.ai.classify({text:'A great day',labels:['positive','negative']}); console.log(result.label);",
            constraints: "Same global and per-app AI gates and budget as completion. Confidence is null because a generative label is not a calibrated probability."
        ),
        .init(
            id: "ai.available",
            title: "AI provider availability",
            keywords: ["AI", "provider", "availability", "budget"],
            purpose: "Check whether the saved app may request configured AI inference.",
            api: "await HTMLAppNative.ai.available()",
            example: "const state = await HTMLAppNative.ai.available(); if (!state.available) showUnavailable();",
            constraints: "Provider identity is hidden from the page. No on-device or streaming support is advertised until implemented."
        ),

        .init(
            id: "capabilities.list",
            title: "Discover supported HTMLApp native APIs",
            keywords: ["capabilities", "permissions", "feature detection", "supported APIs", "native"],
            purpose: "Check the actual supported bridge methods and per-app permission categories before showing a control.",
            api: "await HTMLAppNative.capabilities(); await window.HTMLApp.capabilities()",
            example: """
            const caps = await HTMLAppNative.capabilities();
            if (caps.methods.includes("device.torch") && caps.torchAvailable) {
              // Show a user-operated flashlight control.
            }
            """,
            constraints: "The list only names installed bridge methods; hardware availability and user consent must be checked separately. No automatic permission grants."
        ),
        .init(
            id: "tabs.configure",
            title: "Native UIKit Tab Bar with iOS 26 system appearance",
            keywords: ["tab bar", "liquid glass", "tabs", "bottom navigation", "native navigation"],
            purpose: "Let a saved HTMLApp request a genuine iOS tab bar while its HTML/JavaScript owns each destination screen.",
            api: "HTMLAppNative.tabs.configure(items); HTMLAppNative.tabs.onSelect(handler); HTMLAppNative.tabs.select(id); HTMLAppNative.tabs.update(id,props); HTMLAppNative.tabs.setHidden(hidden); HTMLAppNative.tabs.pulse(); HTMLAppNative.tabs.remove()",
            example: """
            const support = await HTMLAppNative.capabilities();
            if (support.methods.includes("tabs.configure")) {
              HTMLAppNative.tabs.onSelect(id => renderScreen(id));
              await HTMLAppNative.tabs.configure([
                {id:"home",title:"Home",symbol:"house.fill"},
                {id:"settings",title:"Settings",symbol:"gearshape.fill"}
              ]);
            }
            """,
            constraints: "1-7 tabs with unique IDs, titles and catalog SF Symbols. Native system rendering and Liquid Glass on eligible iOS 26 devices are controlled by Apple. HTML must implement each view and a fallback navigation UI when the bridge is absent."
        ),
        .init(
            id: "motion.altitude",
            title: "Barometer and relative altitude",
            keywords: ["altitude", "barometer", "air pressure", "elevation", "pressure kpa"],
            purpose: "Read the available barometer pressure and relative altitude change since sampling started.",
            api: "await HTMLAppNative.motion.altitude()",
            example: "const reading = await HTMLAppNative.motion.altitude(); console.log(reading.relativeAltitudeMeters, reading.pressureKPa);",
            constraints: "Requires per-app Motion permission and supported barometer hardware. Relative altitude is not absolute GPS elevation and may vary with pressure. Unavailable in preview."
        ),
        .init(
            id: "bluetooth.battery",
            title: "Battery of a nearby BLE accessory",
            keywords: ["bluetooth battery", "headphone charge", "accessory battery", "BLE battery level", "peripheral power"],
            purpose: "Read the standard Battery Level characteristic from a nearby BLE device discovered in the same HTMLApp session.",
            api: "await HTMLAppNative.bluetooth.battery(device.id)",
            example: """
            const {devices} = await HTMLAppNative.bluetooth.scan(6);
            for (const device of devices) {
              try {
                const {percentage} = await HTMLAppNative.bluetooth.battery(device.id);
                console.log(device.name, percentage);
              } catch (_) { console.log(device.name, "Battery not available"); }
            }
            """,
            constraints: "User-authorized, foreground Bluetooth only. Reads standard GATT Battery Service 180F / characteristic 2A19, not arbitrary proprietary AirPods or Classic Bluetooth battery values. Connection can fail and an accessory may not expose battery info. Always show unavailable instead of inventing percentage."
        ),
        .init(
            id: "bluetooth.scan",
            title: "Nearby Bluetooth Low Energy discovery",
            keywords: ["bluetooth", "BLE", "peripheral", "nearby device", "scan"],
            purpose: "Discover nearby advertising BLE devices only after an explicit user request.",
            api: "await HTMLAppNative.bluetooth.scan(seconds)",
            example: """
            const support = await HTMLAppNative.capabilities();
            if (support.methods.includes("bluetooth.scan")) {
              const {devices} = await HTMLAppNative.bluetooth.scan(6);
              console.log(devices);
            }
            """,
            constraints: "REQUIRED for nearby Bluetooth in HTMLApp: use HTMLAppNative.bluetooth.scan(6), never navigator.bluetooth.requestDevice or a Web Bluetooth chooser (unavailable in iOS WKWebView). Scan runs after user interaction and permission. Returns {devices:[{id,name,rssi}]}, including an empty array if none advertises. No Classic Bluetooth pairing, connection, accessory battery information, or hidden background scans; only bounded 2–12 second foreground BLE discovery."
        ),
        .init(
            id: "motion.pedometer",
            title: "Motion & Fitness walking steps",
            keywords: ["steps", "pedometer", "walking", "fitness", "motion", "distance"],
            purpose: "Get up to seven days of on-device step counts and available distance/floor totals.",
            api: "await HTMLAppNative.motion.pedometer(days)",
            example: """
            const caps = await HTMLAppNative.capabilities();
            if (caps.methods.includes("motion.pedometer")) {
              const walking = await HTMLAppNative.motion.pedometer(1);
              console.log(walking.steps, walking.distanceMeters);
            }
            """,
            constraints: "Requires this saved HTMLApp's Motion & Steps permission, the iOS Motion & Fitness prompt and supported hardware. Return errors for denied access or missing pedometer. Never query without user intent."
        ),
        .init(
            id: "device.torch",
            title: "Permission-gated iPhone flashlight",
            keywords: ["flashlight", "torch", "light", "camera flash"],
            purpose: "Turn the device flashlight on or off from an explicit user action.",
            api: "await HTMLAppNative.device.torch(true|false)",
            example: """
            const supported = await HTMLAppNative.capabilities();
            if (supported.torchAvailable) await HTMLAppNative.device.torch(true);
            // Always turn it off when the feature ends:
            await HTMLAppNative.device.torch(false);
            """,
            constraints: "Requires this saved HTMLApp's Camera permission plus real iOS camera authorization. Not available on every device. Never turn on automatically."
        ),
        .init(
            id: "device.brightness",
            title: "Display brightness control",
            keywords: ["screen brightness", "display", "dim", "bright", "light"],
            purpose: "Read or adjust screen brightness within user-approved display controls.",
            api: "await HTMLAppNative.device.brightness(level?)",
            example: """
            const before = await HTMLAppNative.device.brightness();
            await HTMLAppNative.device.brightness(0.45);
            await HTMLAppNative.device.brightness(before.level);
            """,
            constraints: "Requires this saved app's Display Control permission; always restore the original brightness when finished."
        ),
        .init(
            id: "device.info",
            title: "Device and runtime information",
            keywords: ["battery", "brightness", "thermal", "low power", "locale", "timezone", "screen", "model", "system version", "runtime"],
            purpose: "Read non-secret runtime details for adaptive UI, diagnostics, battery-aware behavior, locale/time-zone defaults, and screen-aware tools.",
            api: "await HTMLAppNative.device.info()",
            example: """
            const info = await HTMLAppNative.device.info();
            console.log(info.systemVersion, info.batteryLevel, info.lowPowerMode);
            """,
            constraints: "Treat hardware details as hints, not identity or authentication signals."
        ),
        .init(
            id: "device.battery",
            title: "Battery charge and thermal status",
            keywords: ["charging", "plugged in", "battery percentage", "battery state", "thermal state", "overheating", "power"],
            purpose: "Adapt a generated HTML app to current battery charge, external power and device thermal pressure.",
            api: "await HTMLAppNative.device.battery()",
            example: """
            const power = await HTMLAppNative.device.battery();
            console.log(power.percentage, power.charging, power.batteryState, power.thermalState);
            // percentage is null when iOS cannot measure the battery.
            """,
            constraints: "These are live device hints, not continuous background listeners. Poll sparingly while visible; percentage can be null and thermalState may be unknown."
        ),
        .init(
            id: "device.keepAwake",
            title: "Keep the screen awake",
            keywords: ["idle timer", "screen awake", "prevent sleep", "presentation", "timer", "workout", "reader"],
            purpose: "Prevent automatic screen sleep while the user is actively using a timer, presentation, scanner, game, or similar foreground experience.",
            api: "await HTMLAppNative.device.keepAwake(true|false)",
            example: """
            await HTMLAppNative.device.keepAwake(true);
            // Later, when the feature ends:
            await HTMLAppNative.device.keepAwake(false);
            """,
            constraints: "Foreground-only behavior. Always restore false when the feature ends."
        ),
        .init(
            id: "clipboard",
            title: "Native clipboard text",
            keywords: ["copy", "paste", "clipboard", "text"],
            purpose: "Read or write text using the iOS clipboard when a user-facing copy/paste workflow needs native behavior.",
            api: "HTMLAppNative.clipboard.readText(); HTMLAppNative.clipboard.writeText(text)",
            example: """
            await HTMLAppNative.clipboard.writeText("Copied from my HTMLApp");
            const { text } = await HTMLAppNative.clipboard.readText();
            """,
            constraints: "Clipboard reads can still trigger iOS paste privacy behavior; keep reads user-initiated."
        ),
        .init(
            id: "haptics",
            title: "Haptics and vibration",
            keywords: ["haptic", "vibrate", "feedback", "tap", "impact"],
            purpose: "Add short tactile feedback to meaningful user actions.",
            api: "await HTMLAppNative.haptics.play(pattern); navigator.vibrate(pattern)",
            example: """
            await HTMLAppNative.haptics.play([8]);
            // Or the web-compatible bridge:
            navigator.vibrate(8);
            """,
            constraints: "Use briefly and after deliberate interaction. Never make functionality depend on haptics."
        ),
        .init(
            id: "share.present",
            title: "Native iOS share sheet",
            keywords: ["share", "airdrop", "messages", "send", "url", "text"],
            purpose: "Share text or a URL through the native iOS activity sheet.",
            api: "await HTMLAppNative.share.present({ text?, url? })",
            example: """
            const result = await HTMLAppNative.share.present({
              text: "Take a look at this",
              url: "https://example.org"
            });
            """,
            constraints: "This wrapper shares text/URLs. For generated or downloaded files, use the download/export path so HTMLApp retrieves the file and opens the share sheet."
        ),
        .init(
            id: "system.open",
            title: "Open supported system URLs",
            keywords: ["mailto", "tel", "sms", "browser", "open url", "handoff", "phone call", "email"],
            purpose: "Hand a user-initiated URL to iOS for supported schemes such as https:, mailto:, tel:, or sms:.",
            api: "await HTMLAppNative.system.open(url)",
            example: """
            await HTMLAppNative.system.open("mailto:hello@example.org");
            """,
            constraints: "iOS decides whether the URL can be opened. Never present the handoff as a silent/background action."
        ),
        .init(
            id: "externalApps.maps",
            title: "Apple Maps handoff",
            keywords: ["map", "maps", "directions", "navigation", "restaurant", "place", "route", "coordinates", "latitude", "longitude"],
            purpose: "Open Apple Maps to a search, place coordinate, or driving-directions handoff from a deliberate user action.",
            api: "await HTMLAppNative.externalApps.maps({ query?, latitude?, longitude?, name?, directions? })",
            example: """
            await HTMLAppNative.externalApps.maps({
              latitude: 33.4484,
              longitude: -112.0740,
              name: "Destination",
              directions: true
            });
            """,
            constraints: "This hands off to Apple Maps; it does not embed a map inside the HTMLApp. For an in-app map, use a legitimate browser-safe map library/service."
        ),
        .init(
            id: "externalApps.shortcuts",
            title: "Run an installed Shortcut",
            keywords: ["shortcut", "shortcuts", "automation", "workflow", "handoff", "external app"],
            purpose: "Ask iOS Shortcuts to run a user-installed named Shortcut with optional text input.",
            api: "await HTMLAppNative.externalApps.shortcuts(name, input?)",
            example: """
            await HTMLAppNative.externalApps.shortcuts("Log Bike Ride", "12.4 miles");
            """,
            constraints: "The Shortcut must already exist on the device. HTMLApp does not create, install, or silently run arbitrary Shortcuts in the background."
        ),
        .init(
            id: "files.pick",
            title: "Native Files picker",
            keywords: ["file picker", "documents", "import file", "files app", "open document", "multiple files"],
            purpose: "Let the user choose one or more documents from the iOS Files picker and import them into the HTMLApp.",
            api: "await HTMLAppNative.files.pick({ multiple? })",
            example: """
            const files = await HTMLAppNative.files.pick({ multiple: true });
            for (const file of files) {
              const response = await fetch(file.url);
              const bytes = await response.arrayBuffer();
            }
            """,
            constraints: "Returns [{name,url,mimeType,size}]. The url is a local relative URL scoped to the current HTMLApp. Cancellation rejects normally."
        ),
        .init(
            id: "appStorage",
            title: "Portable per-app data storage",
            keywords: ["storage", "portable data", "backup", "share app data", "settings", "notes", "favorites", "records", "onboarding", "json", "persistence"],
            purpose: "Persist important non-secret JSON-compatible user data so it travels with HTMLApp portable packages and restores on another device.",
            api: "HTMLAppNative.appStorage.get(key); appStorage.set(key,value); appStorage.remove(key); appStorage.all(); appStorage.clear()",
            example: """
            const state = (await HTMLAppNative.appStorage.get("state")) ?? { notes: [] };
            state.notes.push({ id: crypto.randomUUID(), text: "Remember this" });
            await HTMLAppNative.appStorage.set("state", state);
            """,
            constraints: "Use for valuable non-secret generated-app state. Keychain secureStorage is for secrets and is intentionally not backed up. localStorage/IndexedDB remain available but are not the preferred portable store."
        ),
        .init(
            id: "widgets",
            title: "Generated Home Screen and Lock Screen widgets",
            keywords: ["widget", "widgets", "home screen", "lock screen", "widgetkit", "glanceable", "live metric", "background refresh", "timeline"],
            purpose: "Publish one or more native WidgetKit widgets from a saved HTMLApp. Widgets can show generated text, metrics, progress, lists, SF Symbols, and embedded images, deep-link back into the originating HTMLApp, and optionally refresh public HTTPS JSON in the background.",
            api: "HTMLAppNative.widgets.configure(definition); widgets.list(); widgets.remove(id?); widgets.reload()",
            example: """
            await HTMLAppNative.widgets.configure({
              id: "bike-status",
              name: "Bike Status",
              primary: true,
              families: ["systemSmall", "systemMedium", "accessoryRectangular"],
              snapshot: {
                layout: "metric",
                eyebrow: "E-BIKE",
                title: "Battery",
                value: "78",
                unit: "%",
                subtitle: "About 31 mi estimated",
                footer: "Updated just now",
                systemSymbol: "bicycle",
                progress: 0.78,
                backgroundHex: "#101820",
                backgroundSecondaryHex: "#1B3445",
                foregroundHex: "#FFFFFF",
                accentHex: "#63D4A7",
                items: [
                  { id: "range", label: "Range", value: "31 mi", systemSymbol: "map" },
                  { id: "odo", label: "Odometer", value: "842 mi", systemSymbol: "gauge" }
                ]
              },
              refresh: {
                url: "https://api.example.org/status",
                intervalMinutes: 30,
                bindings: {
                  "value": "battery.percent",
                  "subtitle": "battery.rangeText",
                  "progress": "battery.fraction",
                  "items.0.value": "battery.rangeText"
                }
              }
            });
            """,
            constraints: "Widget actions: definition.action or snapshot.items[i].action = {id,type: open|route|event,route?,payload?}; definition.openBehavior = openApp|action. Medium/large list rows can each open their own action. On launch, await HTMLAppNative.launch.get() or listen for htmlapplaunch; resolve route and payload from the host, never trust a URL payload. A saved app can publish up to 8 widget definitions, including custom colors, text, images, progress, row lists and ring layouts. The supported Home Screen and Lock Screen widget uses the latest primary snapshot; the broken manual selection gallery has been removed. For a chosen app to appear, publish its widget as primary. Refresh supports public HTTPS GET JSON only, with no embedded secrets or arbitrary JavaScript. Minimum requested interval is 15 minutes, but iOS controls actual delivery. Keep content glanceable; no continuous background HTML execution."
        ),
        .init(
            id: "live.activities",
            title: "Native Live Activities and Dynamic Island",
            keywords: ["live activity", "live activities", "dynamic island", "lock screen activity", "timer", "live progress", "activitykit"],
            purpose: "Show an ongoing user-requested task on the Lock Screen and, on supported iPhones, the Dynamic Island. HTMLApp renders a safe native status, value and optional progress bar, not arbitrary HTML.",
            api: "HTMLAppNative.liveActivities.start(definition); liveActivities.update(id,state); liveActivities.end(id); liveActivities.list()",
            example: """
            // Call from a user action, only for genuinely ongoing work.
            const activity = await HTMLAppNative.liveActivities.start({
              id: "trip-packing", title: "Packing for Rome",
              subtitle: "Preparing luggage", value: "6 / 12",
              progress: 0.5, systemSymbol: "airplane",
              accentHex: "#E69C37",
              secondaryLabel: "Bags packed", secondaryValue: "6 of 12",
              footer: "Tap to open your packing list",
              backgroundHex: "#152437", compactLabel: "6/12"
            });
            await HTMLAppNative.liveActivities.update("trip-packing", {
              subtitle: "Almost ready", value: "10 / 12", progress: 0.83
            });
            // Explicitly end when the task finishes or is cancelled:
            await HTMLAppNative.liveActivities.end("trip-packing");
            """,
            constraints: "Requires iOS 16.2+, Live Activities enabled, a saved app, and consent. Up to three activities per app; supports native text, primary/secondary metrics, progress, SF Symbol, accent color, backgroundHex and compactLabel for the Dynamic Island, and a footer. Design thoughtful activity transitions and update on meaningful state changes, with an explicit end path. Dynamic Island only on supported iPhones; no custom HTML, arbitrary JavaScript, remote push updates, autonomous background execution, or guaranteed real-time refresh. Do not expose private content on the Lock Screen."
        ),
        .init(
            id: "background.fetch",
            title: "Opportunistic background JSON refresh",
            keywords: ["background", "background refresh", "fetch", "scheduled", "periodic", "sync", "refresh", "offline cache", "background task"],
            purpose: "Ask iOS to periodically fetch a public HTTPS JSON endpoint while HTMLApp is not in the foreground, then store the selected result in portable appStorage for the generated app to read later.",
            api: "HTMLAppNative.background.configure(job); background.list(); background.remove(id?); background.refreshNow(id?)",
            example: """
            await HTMLAppNative.background.configure({
              id: "forecast-refresh",
              url: "https://api.example.org/forecast",
              intervalMinutes: 30,
              storageKey: "latestForecast",
              jsonPath: "forecast",
              widgetID: "weather"
            });

            // Test the job immediately while the app is open:
            await HTMLAppNative.background.refreshNow("forecast-refresh");

            // Later, including after an iOS background refresh:
            const cached = await HTMLAppNative.appStorage.get("latestForecast");
            """,
            constraints: "This is iOS-scheduled BGAppRefresh, not a permanently running process. Jobs are opportunistic, minimum requested interval is 15 minutes, and iOS may delay or skip runs due to user settings, battery, Low Power Mode, or system policy. Jobs support public HTTPS GET JSON only and cannot execute arbitrary HTML/JavaScript in the background. One HTMLApp can register at most 6 jobs."
        ),
        .init(
            id: "downloads",
            title: "Downloads, Blob exports, and native save/share",
            keywords: ["download", "export", "blob", "save file", "pdf", "csv", "zip", "generated file", "share file"],
            purpose: "Export generated, fetched, Blob, data-URL, or object-URL content using normal web download semantics; HTMLApp retrieves the completed file and opens the native share sheet.",
            api: "Blob/File + URL.createObjectURL(...) + <a download>; ordinary downloadable URLs also work",
            example: """
            const blob = new Blob([csvText], { type: "text/csv" });
            const url = URL.createObjectURL(blob);
            const a = document.createElement("a");
            a.href = url;
            a.download = "export.csv";
            a.click();
            setTimeout(() => URL.revokeObjectURL(url), 1000);
            """,
            constraints: "Use a meaningful filename and MIME type. Do not claim the file was saved before the native share/export flow is triggered."
        ),
        .init(
            id: "contacts",
            title: "Contacts picker, list, and create",
            keywords: ["contact", "contacts", "address book", "phone number", "email address", "people"],
            purpose: "Pick one contact, read authorized contacts when bulk access is core to the feature, or create a new real contact.",
            api: "HTMLAppNative.contacts.pick(); contacts.list({limit?}); contacts.create({...})",
            example: """
            const person = await HTMLAppNative.contacts.pick();

            const contacts = await HTMLAppNative.contacts.list({ limit: 200 });

            await HTMLAppNative.contacts.create({
              givenName: "Alex",
              familyName: "Rivera",
              phones: [{ label: "mobile", value: "+15551234567" }],
              emails: [{ label: "home", value: "alex@example.org" }]
            });
            """,
            constraints: "Prefer pick() for one-contact workflows. list() is sensitive and should be requested only after a clear user action. Handle permission denial and empty results."
        ),
        .init(
            id: "photos",
            title: "Photos picker and save to Photos",
            keywords: ["photo", "photos", "image", "video", "gallery", "camera roll", "save image", "save video"],
            purpose: "Let the user select photos/videos with the native picker or save a local imported/generated media file into Photos.",
            api: "HTMLAppNative.photos.pick({limit?,media?}); HTMLAppNative.photos.save(localURL)",
            example: """
            const picked = await HTMLAppNative.photos.pick({ limit: 4, media: "images" });
            const first = picked[0];
            if (first) await HTMLAppNative.photos.save(first.url);
            """,
            constraints: "media is images, videos, or any. The picker is user-mediated; it does not expose unrestricted hidden library enumeration or deletion."
        ),
        .init(
            id: "calendar",
            title: "Calendar events",
            keywords: ["calendar", "event", "appointment", "schedule", "meeting", "eventkit"],
            purpose: "Create, query, update, or delete real iOS calendar events.",
            api: "calendar.createEvent({...}); calendar.events({...}); calendar.updateEvent({...}); calendar.deleteEvent(id)",
            example: """
            const event = await HTMLAppNative.calendar.createEvent({
              title: "Project review",
              start: "2026-10-06T17:00:00Z",
              end: "2026-10-06T17:30:00Z",
              notes: "Created by this HTMLApp"
            });

            const events = await HTMLAppNative.calendar.events({
              start: "2026-10-01T00:00:00Z",
              end: "2026-11-01T00:00:00Z",
              limit: 100
            });

            await HTMLAppNative.calendar.updateEvent({ id: event.id, title: "Updated review" });
            await HTMLAppNative.calendar.deleteEvent(event.id);
            """,
            constraints: "Requires permission. Dates may be ISO-8601 strings or Unix timestamps. Handle deleted/missing items."
        ),
        .init(
            id: "reminders",
            title: "Reminders",
            keywords: ["reminder", "todo", "task", "due date", "eventkit"],
            purpose: "Create, list, update, or delete real iOS reminders.",
            api: "reminders.create({...}); reminders.list({limit?}); reminders.update({...}); reminders.delete(id)",
            example: """
            const created = await HTMLAppNative.reminders.create({
              title: "Submit report",
              due: "2026-10-07T16:00:00Z"
            });
            const reminders = await HTMLAppNative.reminders.list({ limit: 100 });
            await HTMLAppNative.reminders.update({ id: created.id, notes: "Bring attachments" });
            """,
            constraints: "Requires permission. Treat cancellation, denial, empty lists, and missing reminders as normal states."
        ),
        .init(
            id: "push.register",
            title: "Register for remote APNs alerts",
            keywords: ["remote notifications", "push message", "APNs", "server notifications"],
            purpose: "Opt in to iOS push notifications and obtain a device token for the user's own server.",
            api: "await HTMLAppNative.push.register()",
            example: """
            try {
              const registration = await HTMLAppNative.push.register();
              // Send registration.token and the app ID to a server you control.
              console.log('APNs registration ready', registration.appID);
            } catch (error) { console.log(error.message); }
            """,
            constraints: "Requires iOS notification permission, a provisioning profile with aps-environment entitlement, a paid Apple developer setup and an APNs-enabled backend. An APNs token alone cannot send pushes or keep HTML JavaScript running. Do not embed Apple private keys in generated HTML."
        ),
        .init(
            id: "notifications.schedule",
            title: "Local notifications and scheduling",
            keywords: ["notification", "notify", "alert later", "schedule notification", "timer alert", "local notification"],
            purpose: "Schedule or cancel real local iOS notifications for this HTMLApp.",
            api: "HTMLAppNative.notifications.schedule({...}); HTMLAppNative.notifications.cancel({id?})",
            example: """
            const n = await HTMLAppNative.notifications.schedule({
              id: "tea-timer",
              title: "Tea is ready",
              body: "Your 4 minute timer finished.",
              afterSeconds: 240
            });
            await HTMLAppNative.notifications.cancel({ id: n.id });
            """,
            constraints: "Local notifications only. This does not provide remote push or arbitrary background execution. Ask permission in context."
        ),
        .init(
            id: "biometrics.authenticate",
            title: "Face ID, Touch ID, or device authentication",
            keywords: ["face id", "touch id", "biometric", "authentication", "unlock", "local authentication"],
            purpose: "Gate a sensitive local action behind iOS device-owner authentication.",
            api: "await HTMLAppNative.biometrics.authenticate({reason?,biometricsOnly?})",
            example: """
            const result = await HTMLAppNative.biometrics.authenticate({
              reason: "Unlock your private notes"
            });
            if (result.authenticated) showPrivateContent();
            """,
            constraints: "Authentication success proves only local device authentication for that action; it is not a user account or identity service."
        ),
        .init(
            id: "secureStorage",
            title: "Per-HTMLApp secure string storage",
            keywords: ["keychain", "secret", "token", "credential", "secure storage", "password"],
            purpose: "Store small secrets or tokens in a per-HTMLApp Keychain-backed store instead of localStorage.",
            api: "secureStorage.set(key,value); secureStorage.get(key); secureStorage.remove(key)",
            example: """
            await HTMLAppNative.secureStorage.set("access-token", token);
            const { value } = await HTMLAppNative.secureStorage.get("access-token");
            await HTMLAppNative.secureStorage.remove("access-token");
            """,
            constraints: "String values only and intended for small secrets/tokens, not bulk data. Do not log secret values."
        ),
        .init(
            id: "speech",
            title: "Native text-to-speech",
            keywords: ["speech", "speak", "text to speech", "tts", "voice", "read aloud"],
            purpose: "Speak app text with AVSpeechSynthesizer and stop playback when needed.",
            api: "HTMLAppNative.speech.speak(text,{language?,rate?,pitch?}); speech.stop()",
            example: """
            await HTMLAppNative.speech.speak("Navigation started", {
              language: "en-US",
              rate: 0.45,
              pitch: 1.0
            });
            // Later:
            await HTMLAppNative.speech.stop();
            """,
            constraints: "Do not assume a particular installed voice. Start speech as a meaningful user-facing action."
        ),
        .init(
            id: "camera.microphone",
            title: "Camera and microphone",
            keywords: ["camera", "microphone", "mic", "record", "scanner", "video", "audio capture", "selfie", "rear camera"],
            purpose: "Capture live camera/microphone media, build scanners, recorders, meters, or camera-driven tools.",
            api: "navigator.mediaDevices.getUserMedia(constraints); MediaRecorder/Web Audio when feature-detected",
            example: """
            const stream = await navigator.mediaDevices.getUserMedia({
              video: { facingMode: { ideal: "environment" } },
              audio: false
            });
            video.srcObject = stream;
            // Cleanup:
            stream.getTracks().forEach(track => track.stop());
            """,
            constraints: "Request only after a meaningful user gesture, handle denial/unavailability, and always stop tracks when finished."
        ),
        .init(
            id: "geolocation",
            title: "Foreground geolocation",
            keywords: ["location", "gps", "coordinates", "latitude", "longitude", "position", "tracking", "map"],
            purpose: "Get a one-time native location fix or foreground position updates.",
            api: "navigator.geolocation.getCurrentPosition(...); navigator.geolocation.watchPosition(...); clearWatch(...)",
            example: """
            navigator.geolocation.getCurrentPosition(
              position => usePosition(position.coords),
              error => showLocationError(error),
              { enableHighAccuracy: true, timeout: 15000 }
            );
            """,
            constraints: "Foreground use only. Handle denied, unavailable, and timeout states. Clear watches when no longer needed."
        ),
        .init(
            id: "motion.orientation.compass",
            title: "Motion, orientation, and compass",
            keywords: ["accelerometer", "gyroscope", "motion", "orientation", "compass", "heading", "tilt", "sensor"],
            purpose: "Build tilt controls, motion-reactive experiences, heading/compass UI, and sensor-driven interactions.",
            api: "DeviceMotionEvent / DeviceOrientationEvent; window.htmlappCompassHeading; htmlappcompass event",
            example: """
            if (typeof DeviceOrientationEvent?.requestPermission === "function") {
              await DeviceOrientationEvent.requestPermission();
            }
            window.addEventListener("htmlappcompass", event => {
              console.log(event.detail.heading, event.detail.accuracy);
            });
            """,
            constraints: "Permission requests must come from a user gesture when required. Remove listeners when finished and never fabricate sensor values."
        ),
        .init(
            id: "file.input",
            title: "Web file and media input",
            keywords: ["input file", "upload local", "choose image", "choose audio", "choose video", "capture hint"],
            purpose: "Use standard file inputs for user-mediated imports when a native picker wrapper is unnecessary.",
            api: "<input type=\"file\"> plus File/Blob/FileReader/arrayBuffer()/text()/object URLs",
            example: """
            <input id="picker" type="file" accept="image/*" multiple>
            <script>
              picker.addEventListener("change", () => {
                for (const file of picker.files) console.log(file.name, file.type, file.size);
              });
            </script>
            """,
            constraints: "The user chooses the files. Do not claim unrestricted filesystem or Photo Library access."
        ),
        .init(
            id: "storage",
            title: "Local persistence and offline data",
            keywords: ["localstorage", "indexeddb", "cache", "offline", "database", "blob storage", "settings", "drafts"],
            purpose: "Persist preferences, drafts, cached responses, projects, histories, and larger structured/blob data locally.",
            api: "localStorage for small values; IndexedDB for structured/blob data; navigator.storage when available",
            example: """
            localStorage.setItem("units", "metric");
            // Use IndexedDB for projects, histories, or Blob-heavy data.
            """,
            constraints: "Do not store secrets in localStorage. Feature-detect optional storage APIs and handle quota/eviction."
        ),
        .init(
            id: "networking",
            title: "Networking and realtime",
            keywords: ["fetch", "http", "websocket", "eventsource", "sse", "realtime", "api", "network"],
            purpose: "Call browser-safe public services or a real user/service backend and support realtime connections.",
            api: "fetch; WebSocket; EventSource",
            example: """
            const controller = new AbortController();
            const response = await fetch(apiURL, { signal: controller.signal });
            if (!response.ok) throw new Error("Request failed");
            const data = await response.json();
            """,
            constraints: "CORS, authentication, endpoint documentation, and service limits still apply. Never embed private server secrets."
        ),
        .init(
            id: "media.audio",
            title: "Audio, video, Web Audio, and media session",
            keywords: ["audio", "video", "music", "player", "web audio", "media session", "waveform", "playback"],
            purpose: "Build media players, audio tools, waveform/visualizer experiences, synthesis, and recording workflows.",
            api: "<audio>/<video>, Web Audio API, MediaRecorder, Media Session when feature-detected",
            example: """
            const ctx = new AudioContext();
            await ctx.resume();
            // Build nodes/analysis only after user interaction when audio policy requires it.
            """,
            constraints: "Respect autoplay restrictions, clean up nodes/streams, and feature-detect optional Media Session behavior."
        ),
        .init(
            id: "credentials",
            title: "Credentials, passkeys, and OAuth",
            keywords: ["login", "oauth", "passkey", "webauthn", "credential", "sign in", "authentication server"],
            purpose: "Use standards-based authentication when a real service/backend exists.",
            api: "navigator.credentials / WebAuthn when supported; OAuth Authorization Code + PKCE for compatible services",
            example: """
            if ("credentials" in navigator) {
              // Use only with a real relying-party/backend configuration.
            }
            """,
            constraints: "Never invent login success, users, tokens, or account state. Passkeys require a real relying party and correct secure-origin/server setup; never embed client secrets."
        ),
        .init(
            id: "optional.web.capabilities",
            title: "Optional WebKit capabilities",
            keywords: ["wake lock", "service worker", "cache api", "webgpu", "webgl", "usb", "serial", "hid", "fullscreen", "picture in picture", "network information"],
            purpose: "Use optional browser APIs only when feature detection proves the relevant object/method is present and the app has a usable fallback.",
            api: "Feature-detect the specific standard browser API before use",
            example: """
            if ("wakeLock" in navigator) {
              try { const lock = await navigator.wakeLock.request("screen"); } catch (_) {}
            }
            """,
            constraints: "Object presence does not guarantee a particular operation succeeds on the current iOS/WebKit version or context. For Bluetooth discovery specifically, use HTMLAppNative.bluetooth.scan, never Web Bluetooth."
        ),
        .init(
            id: "unsupported.entitlements",
            title: "Capabilities not currently exposed to generated HTMLApps",
            keywords: ["healthkit", "health", "homekit", "nfc", "core nfc", "nearby interaction", "background execution", "background location", "live activity", "live activities", "dynamic island", "remote push", "callkit", "carplay", "apple pay", "device management", "secure enclave", "background task", "activitykit", "widgetkit"],
            purpose: "Recognize requests that need an iOS entitlement/framework which HTMLApp does not currently expose through a documented bridge.",
            api: "No generated-JavaScript bridge is currently documented for these capabilities.",
            example: """
            // Do not invent window.htmlappLiveActivity, HTMLAppNative.health, or similar APIs.
            // Use an honest user-mediated/web fallback, or surface the limitation.
            """,
            constraints: "An iOS capability existing at the native platform level does not make it available to a generated HTMLApp. Only documented bridges are guaranteed."
        )
    ]

    // Planner queries can request the whole catalog or a focused capability section.
    // These are documentation lookups during generation, not permission requests.
    private static let sections: [(name: String, ids: [String])] = [
        ("carplay", ["display.environment", "tabs.configure", "speech"]),
        ("bluetooth", ["bluetooth.scan", "bluetooth.battery"]),
        ("widgets", ["widgets", "live.activities", "background.fetch"]),
        ("tabs", ["tabs.configure"]),
        ("device", ["device.info", "device.battery", "device.torch", "device.brightness", "device.keepAwake", "motion.altitude", "motion.pedometer"]),
        ("motion", ["motion.altitude", "motion.pedometer", "motion.orientation.compass"]),
        ("storage", ["appStorage", "secureStorage", "storage", "clipboard"]),
        ("personal data", ["contacts", "photos", "files.pick", "calendar", "reminders"]),
        ("notifications", ["notifications.schedule", "push.register", "live.activities"]),
        ("media", ["camera.microphone", "media.audio", "speech", "photos"]),
        ("network", ["networking", "geolocation", "externalApps.maps", "externalApps.shortcuts"]),
        ("interface", ["tabs.configure", "haptics", "share.present", "system.open", "speech"]),
        ("security", ["biometrics.authenticate", "secureStorage", "credentials"])
    ]

    static var capabilityDirectory: String {
        let labels = sections.map { $0.name }.joined(separator: ", ")
        return "Available capability documentation sections: " + labels
            + ". Request <device_query>all capabilities</device_query> for the complete built-in reference, or request one or more specific sections (for example bluetooth, widgets, tabs, device, or storage). This requests documentation only; the generated app must still check capabilities and obtain user permissions."
    }

    static func research(queries: [String], maxMatchesPerQuery: Int = 6) -> String {
        var seenQueries = Set<String>()
        let uniqueQueries = queries
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seenQueries.insert($0.lowercased()).inserted }

        guard !uniqueQueries.isEmpty else { return "" }

        var sections: [String] = [
            "HTMLAPP DEVICE API CATALOG RESULTS",
            "These results are generated from HTMLApp's built-in capability catalog. Treat exact method names, examples, and limitations below as authoritative for generated HTMLApps."
        ]

        for query in uniqueQueries.prefix(8) {
            let normalized = query.lowercased()
            if ["all", "all capabilities", "everything", "full catalog", "all native apis", "all htmlapp capabilities"].contains(normalized) {
                sections.append("DEVICE QUERY: " + query + "\n" + entries.map { $0.renderedReference }.joined(separator: "\n\n"))
                continue
            }
            let matchingSections = Self.sections.filter { item in
                normalized == item.name || normalized == item.name + " capabilities"
                    || normalized == item.name + " apis"
                    || normalized == item.name + " section"
                    || (item.name == "tabs" && normalized == "tab bar")
                    || (item.name == "device" && normalized == "device info")
            }
            if !matchingSections.isEmpty {
                let ids = Set(matchingSections.flatMap { $0.ids })
                sections.append("DEVICE QUERY: " + query + "\n" + entries.filter { ids.contains($0.id) }.map { $0.renderedReference }.joined(separator: "\n\n"))
                continue
            }
            let terms = searchTerms(query)
            let normalizedQuery = query.lowercased()

            let ranked = entries.compactMap { entry -> (score: Int, entry: HTMLAppDeviceAPICatalogEntry)? in
                let haystack = entry.searchableText
                var score = 0
                if haystack.contains(normalizedQuery) { score += 12 }
                for term in terms {
                    if entry.id.lowercased().contains(term) { score += 7 }
                    if entry.title.lowercased().contains(term) { score += 6 }
                    if entry.keywords.contains(where: { $0.lowercased().contains(term) }) { score += 5 }
                    if entry.purpose.lowercased().contains(term) { score += 3 }
                    if entry.api.lowercased().contains(term) { score += 2 }
                }
                return score > 0 ? (score, entry) : nil
            }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.entry.title < $1.entry.title
            }

            var lines = ["DEVICE QUERY: \(query)"]
            if ranked.isEmpty {
                lines.append("No matching built-in capability was found. Do not invent a native bridge; use a verified browser/public API fallback or expose the limitation.")
            } else {
                lines.append(contentsOf: ranked.prefix(max(1, maxMatchesPerQuery)).map { $0.entry.renderedReference })
            }
            sections.append(lines.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n")
    }

    private static func searchTerms(_ query: String) -> [String] {
        let raw = query
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        var seen = Set<String>()
        return raw.filter {
            $0.count > 2 &&
            !stopWords.contains($0) &&
            seen.insert($0).inserted
        }
    }
}


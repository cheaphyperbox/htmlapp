# On-device Vision bridge

Saved HTML apps may call `HTMLAppNative.vision.recognizeText(imageDataURL)`, `scanCodes(imageDataURL)`, `classifyImage(imageDataURL)`, and `detectFaces(imageDataURL)` on user-supplied `data:image/...;base64,...` images. The native bridge limits encoded input to 8 MiB and downsamples images above 1600 pixels on the longest side. Apple Vision processing runs locally. OCR returns text, confidence and normalized boxes; barcode scan returns values and symbologies; classification returns up to eight categories; face detection returns count and boxes only, never identity.

These methods do not open the camera or photo library; use the existing user-initiated photo picker or browser file input to acquire an image. Failures use `invalid_image` or `vision_unavailable`. Generated apps must check `capabilities().methods` and display unavailable states.

## Needs device testing

On an iPhone running iOS 16 or newer, open a saved HTML app with a photo/file input, supply a receipt, QR code, ordinary object and group photo, then call each method. Check that returned boxes align with images, large images do not crash, unsupported formats fail cleanly, and no network traffic occurs. Xcode compilation and physical-device behavior are not verified.

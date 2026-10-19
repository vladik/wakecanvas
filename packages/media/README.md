# @wakecanvas/media

Optional browser-side image preparation for WakeCanvas Experiences. It decodes,
resizes, masks, and encodes on the participant device in a Web Worker; Phoenix
receives only bounded output. Experiences embed the package in their own assets,
so it adds no kiosk runtime dependency.

The first backend is deterministic edge-connected chroma removal for controlled
green, blue, white, or grey backgrounds. It is deliberately not ML segmentation.

Run the zero-dependency golden-mask fixture suite with Node.js 24 or newer:

```sh
npm test
```

The fixtures cover controlled green and blue screens, a white light box,
shadowed/textured backgrounds, an object touching an image edge, translucent
foreground pixels, and oversized-input rejection.

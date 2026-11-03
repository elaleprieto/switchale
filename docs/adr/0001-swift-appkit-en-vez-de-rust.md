# Swift + AppKit en vez de Rust

El repo arrancó como un proyecto Rust (`cargo new`), pero switchale se escribe en Swift con AppKit. Todo lo que hace la app (Accessibility/AXUIElement, CGEventTap, ScreenCaptureKit, un `NSPanel` que aparece en menos de 100 ms) es API nativa de Apple. En Rust habría que pasar todo por `objc2` con FFI y `unsafe`, y no había una razón para preferir Rust en este proyecto.

## Considered Options

- **Rust + `objc2`**: descartado por el costo de FFI y porque hay pocos ejemplos para estas APIs.
- **Tauri**: descartado porque un webview es demasiado lento para un overlay que tiene que aparecer al instante.

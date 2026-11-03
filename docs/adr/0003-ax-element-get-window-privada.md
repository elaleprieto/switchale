# `_AXUIElementGetWindow` privada para ids de Window

Para cruzar una Window de Accessibility (`AXUIElement`) con la de `CGWindowList` (orden de apilamiento, capa, pantalla) hace falta su `CGWindowID`. macOS solo lo expone por la API privada `_AXUIElementGetWindow` de ApplicationServices; no hay alternativa pública razonable (comparar títulos y frames es frágil e ambiguo). Es una segunda excepción acotada al criterio de [ADR-0002](0002-apis-privadas-solo-para-spaces.md): switchale es de uso personal y no va a la App Store. Para acotar el daño cuando una versión de macOS la rompa, queda aislada en un único archivo (`Sources/Switchale/AX.swift`) junto con los helpers compartidos de AX; el resto de la app y el núcleo solo ven `WindowID`.

## Considered Options

- **Heurística por título y frame**: descartada porque es ambigua con Windows del mismo título y se rompe con cada animación.
- **Solo CGWindowList, sin AX**: descartada porque no permite activar ni leer Minimized.

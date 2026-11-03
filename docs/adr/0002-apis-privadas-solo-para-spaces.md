# APIs privadas de SkyLight, solo para Spaces

Las APIs públicas de macOS no exponen las Windows de otros Spaces. Para soportar la opción "incluir ventanas de otros Spaces" usamos APIs privadas de SkyLight (`CGSCopySpaces`, `CGSCopyWindowsWithOptionsAndTags`). Lo aceptamos porque switchale es de uso personal y no va a la App Store. Para acotar el daño cuando una versión de macOS las rompa, quedan aisladas en un único módulo que se usa solo para esa opción, que está desactivada por defecto. El resto de la app no depende de ellas. Ese módulo es `Sources/Switchale/Spaces.swift`: resuelve los símbolos con `dlsym` (sin linkear SkyLight) y, si faltan o fallan, la app se comporta como con la opción desactivada. Para activar una Window de otro Space (y que macOS cambie a ese Space) usa además `_SLPSSetFrontProcessWithOptions` y `SLPSPostEventRecordTo`, en el mismo módulo.

La única otra excepción es `_AXUIElementGetWindow`, autorizada en [ADR-0003](0003-ax-element-get-window-privada.md).

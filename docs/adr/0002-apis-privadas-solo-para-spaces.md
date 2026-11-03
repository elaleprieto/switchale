# APIs privadas de SkyLight, solo para Spaces

Las APIs públicas de macOS no exponen las Windows de otros Spaces. Para soportar la opción "incluir ventanas de otros Spaces" usamos APIs privadas de SkyLight (`CGSCopySpaces`, `CGSCopyWindowsWithOptionsAndTags`). Lo aceptamos porque switchale es de uso personal y no va a la App Store. Para acotar el daño cuando una versión de macOS las rompa, quedan aisladas en un único módulo que se usa solo para esa opción, que está desactivada por defecto. El resto de la app no depende de ellas.

# switchale

Window Switcher para macOS: reemplaza ⌘⇥ con un panel que lista Windows (no Apps). Vocabulario en `GLOSSARY.md`, decisiones en `docs/adr/`.

## Requisitos

- macOS 14 o posterior, Xcode 27
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- El certificado "Apple Development: prietoale@icloud.com" (team `WDHDK3HJZ3`) en el llavero

## Proyecto

`project.yml` define el proyecto; `Switchale.xcodeproj` se genera con `xcodegen generate` y no se versiona. Targets:

- `Switchale`: la app de barra de menú (AppKit).
- `SwitchaleCore`: el núcleo del switcher, Swift puro (no importa AppKit, AX ni CoreGraphics).
- `SwitchaleCoreTests`: tests de Swift Testing del núcleo.

## Compilar

```sh
scripts/build.sh            # Debug
scripts/build.sh Release
```

Genera el proyecto y compila `build/DerivedData/Build/Products/<config>/switchale.app`, firmada con Apple Development (no ad-hoc), así los permisos de Accesibilidad y Grabación de pantalla sobreviven a las recompilaciones. Para verificar la firma:

```sh
codesign -dv build/DerivedData/Build/Products/Debug/switchale.app
```

## Tests

```sh
scripts/test.sh
```

Corre los tests del núcleo con `xcodebuild test -scheme SwitchaleCore`. No necesitan permisos.

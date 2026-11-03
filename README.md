# switchale

Window Switcher para macOS: reemplaza ⌘⇥ con un panel que lista Windows (no Apps). Vocabulario en `GLOSSARY.md`, decisiones en `docs/adr/`.

## Requisitos

- macOS 14 o posterior, Xcode 27
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- El certificado "Apple Development: prietoale@icloud.com" (team WDHDK3HJZ3) en el llavero

## Proyecto

`project.yml` define el proyecto; `Switchale.xcodeproj` se genera con `xcodegen generate` y no se versiona. Targets:

- `Switchale`: la app de barra de menú (AppKit).
- `SwitchaleCore`: el núcleo del Window Switcher, Swift puro (no importa AppKit, AX ni CoreGraphics).
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

## Permisos e inicio al loguearse

Si falta Accesibilidad, al arrancar se abre la ventana de permisos; si solo falta Grabación de pantalla, solo en el primer arranque (siempre se puede abrir desde "Permisos…" en el menú). El primer clic en el botón de un permiso lo pide; los siguientes abren el panel de Configuración del Sistema. La ventana se actualiza sola cada segundo; como macOS puede no informar Grabación de pantalla hasta reabrir la app, una vez pedida ofrece "Reabrir switchale". Lo ya pedido y el primer arranque se guardan en `UserDefaults` (`requestedAccessibility`, `requestedScreenRecording`, `hasLaunched`). switchale se registra como login item (`SMAppService`) salvo que la preferencia `launchAtLogin` sea `NO`; para probar sin registrarlo:

```sh
build/DerivedData/Build/Products/Debug/switchale.app/Contents/MacOS/switchale -launchAtLogin NO
```

## Configuración del Window Switcher

Todavía no hay control en Preferencias (#12): se cambia con `defaults write` y se aplica sin reiniciar la app (en la siguiente Switch Session).

- `includesOtherScreens` (Bool, por defecto `YES`): si es `NO`, solo entran las Windows de la pantalla actual, que es la de la Window con foco (o la del mouse si no hay una).
- `panelScreen` (`focusedWindow` por defecto, `mouse` o `primary`): en qué pantalla aparece el Window Switcher. Se decide al empezar la Switch Session y no cambia mientras dura.

```sh
defaults write <bundle id> includesOtherScreens -bool NO
defaults write <bundle id> panelScreen -string mouse
```

## Tests

```sh
scripts/test.sh
```

Primero falla si algún archivo de `Sources/SwitchaleCore` importa AppKit, Cocoa, ApplicationServices, CoreGraphics o Carbon; después corre los tests del núcleo con `xcodebuild test -scheme SwitchaleCore`. No necesitan permisos.

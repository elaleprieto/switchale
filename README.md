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

Se cambia en "Preferencias…" (barra de menú), con las pestañas General (Hotkey y activación de cada Scope, Activation Delay, pantalla del panel, inclusiones e inicio al loguearse) y Appearance (tamaño de Thumbnail), y el botón "Restaurar valores por defecto". Todo se guarda en `UserDefaults` y se aplica sin reiniciar la app, desde la siguiente Switch Session. También se puede cambiar con `defaults write`:

- `allWindowsEnabled`, `currentAppEnabled` (Bool, por defecto `YES`): si es `NO`, el Hotkey del Scope hace lo que hace en macOS.
- `allWindowsHotkeyModifier`, `currentAppHotkeyModifier` (`command`, `option`, `control` o `shift`) y `allWindowsHotkeyKey`, `currentAppHotkeyKey` (`tab` o `grave`): por defecto ⌘⇥ y ⌥`. Con ⇥ (y un modificador que no sea ⇧), el Hotkey con ⇧ retrocede. Los dos Scopes no pueden tener el mismo Hotkey: Preferencias no ofrece el del otro Scope (aunque esté desactivado); si se repite con `defaults write`, abre All Windows.
- `activationDelayMilliseconds` (Int, 0 a 500 de a 10, por defecto `80`).
- `includesMinimizedWindows`, `includesHiddenApps`, `includesOtherScreens` (Bool, por defecto `YES`): las Minimized Windows van al final, así que un Quick Switch solo salta a una si no hay otra; sin otras pantallas, solo entran las Windows de la pantalla actual, que es la de la Window con foco (o la del mouse si no hay una).
- `includesOtherSpaces` (Bool, por defecto `NO`): incluir las Windows de otros Spaces; activar una te lleva a su Space. Usa APIs privadas de SkyLight (ADR-0002), aisladas en `Sources/Switchale/Spaces.swift` y solo con la opción activada; si no están o fallan, es como si la opción estuviera desactivada.
- `panelScreen` (`focusedWindow` por defecto, `mouse` o `primary`): en qué pantalla aparece el Window Switcher. Se decide al empezar la Switch Session y no cambia mientras dura.
- `thumbnailWidth` (Int, 96 a 224 de a 16, por defecto `160`): ancho de las Thumbnails; el alto sigue la proporción 16:10.

```sh
defaults write <bundle id> includesOtherScreens -bool NO
defaults write <bundle id> panelScreen -string mouse
```

## Tests

```sh
scripts/test.sh
```

Primero falla si algún archivo de `Sources/SwitchaleCore` importa AppKit, Cocoa, ApplicationServices, CoreGraphics o Carbon; después corre los tests del núcleo con `xcodebuild test -scheme SwitchaleCore`. No necesitan permisos.

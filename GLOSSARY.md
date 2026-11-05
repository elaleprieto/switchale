# switchale

Window switcher para macOS: reemplaza ⌘⇥ con un panel que lista ventanas (no apps), con miniaturas, para saltar directo a la ventana que querés.

## Language

### Ventanas y apps

**Window**:
Una ventana de primer nivel de una App a la que el usuario puede querer saltar.
_Avoid_: Tab, document

**App**:
Una aplicación en ejecución que es dueña de cero o más Windows.
_Avoid_: Process, program

**Minimized Window**:
Una Window que está en el Dock; sigue siendo un destino válido del switcher.

**Hidden App**:
Una App ocultada con ⌘H; sus Windows siguen existiendo pero no están en pantalla.

**Windowless App**:
Una App en ejecución sin Windows abiertas. Aparece al final del Scope All Windows como una entrada con el ícono de la App; activarla equivale a hacer clic en su ícono del Dock. Finder y switchale nunca son Windowless Apps: corren siempre, así que sin Windows no aparecen.

**Space**:
Un escritorio virtual de macOS. Las Windows de otros Spaces están excluidas por defecto.
_Avoid_: Desktop, workspace

### El switcher

**Window Switcher**:
El panel propio de switchale que muestra Windows para elegir una mientras se mantiene el modificador del Hotkey. Arriba van las Windows abiertas; abajo, desde una fila nueva y separadas por una línea, las Minimized Windows y las Windowless Apps.
_Avoid_: App Switcher, switcher panel

**App Switcher**:
El ⌘⇥ nativo de macOS, que lista Apps. No es parte de switchale; switchale lo reemplaza.

**Scope**:
Qué Windows entran en el Window Switcher: **All Windows** (todas las Apps) o **Current App** (solo las Windows de la App activa). Cada Scope tiene su propio Hotkey.
_Avoid_: Mode, filter

**Switch Session**:
Lo que pasa entre apretar el Hotkey y soltar el modificador. Termina en un Quick Switch, en la activación de la Window seleccionada, o en una cancelación con Esc.
_Avoid_: Gesture, interaction

**Recency Order**:
El orden de las Windows en el Window Switcher: la usada más recientemente primero, con las Minimized Windows al final (también de la más reciente a la menos reciente).
_Avoid_: Z-order, MRU list

**Quick Switch**:
Tocar y soltar el Hotkey antes del Activation Delay: salta a la siguiente Window en Recency Order sin mostrar el Window Switcher.

**Activation Delay**:
El tiempo que hay que mantener el Hotkey antes de que aparezca el Window Switcher.

**Thumbnail**:
La imagen en miniatura del contenido de una Window que se muestra en el Window Switcher. Si no hay Thumbnail disponible, se muestra el ícono de la App y el título de la Window.
_Avoid_: Preview, snapshot

**Grabación de pantalla** (Screen Recording):
El permiso de macOS que hace falta para capturar el contenido de otras Windows. Sin él no hay Thumbnails y el Window Switcher muestra solo el ícono y el título.
_Avoid_: Screen capture permission

**Screen**:
Una pantalla (monitor). La pantalla actual es la de la Window con foco o, si no hay una, la del mouse; el Window Switcher aparece en la que elige la configuración y no cambia durante la Switch Session.
_Avoid_: Display, monitor

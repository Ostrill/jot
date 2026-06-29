# Jot: Полная техническая документация проекта

## 1. Что это за проект

`Jot` — нативное macOS-приложение на `Swift + AppKit`, собранное в один файл `main.swift`.

Изначально задумывался как демонстрация `Liquid Glass` эффекта, похожего на Dock в macOS Tahoe. В процессе эволюционировал в компактный стеклянный текстовый редактор:

- стеклянная панель на публичных API AppKit (`NSGlassEffectView`);
- редактируемый текст поверх glass-эффекта;
- меню в menu bar;
- rainbow-окраска панели — включая анимацию иконки в Dock;
- сохранение и открытие файлов;
- индикатор несохранённых изменений (символ `✶` в правом верхнем углу);
- wrap guides для визуализации перенесённых строк.

---

## 2. Структура репозитория

```
jot/                    ← рабочая директория
├── main.swift                  ← весь исходный код приложения (~1656 строк)
├── icon.png                    ← исходная иконка (прозрачный PNG 1024×1024)
├── rebuild_with_icon.sh        ← пересборка с готовым .icns файлом
├── rebuild.sh                  ← пересборка из icon.png + выбранный цвет фона
├── PROJECT_DOCUMENTATION.md   ← этот файл
├── task.md                     ← история самых ранних экспериментов
├── Jot.app/                    ← готовый app bundle
│   └── Contents/
│       ├── Info.plist
│       ├── MacOS/GlassPanel    ← скомпилированный бинарник
│       └── Resources/
│           ├── AppIcon.icns    ← иконка с запечённым тёмным фоном
│           ├── icon.icns       ← копия AppIcon.icns (legacy)
│           └── BaseIcon.png    ← оригинальный icon.png (для Dock-анимации)
├── icons/                      ← архив вариантов иконок (.icns)
│   └── v20.icns и другие
├── build_icon/                 ← рабочая директория для сборки иконки
│   ├── AppIcon.iconset/        ← все 10 размеров PNG
│   ├── icon_composited.png     ← composite = icon.png + background
│   └── composite               ← скомпилированный Swift-инструмент
└── icon_picker/
    └── main.swift              ← исходник IconPicker.app
IconPicker.app/                 ← утилита подбора фона иконки
```

Проект намеренно плоский: без Xcode project, без asset catalog, без storyboard.

---

## 3. Как собирать и обновлять приложение

### 3.1. Быстрая компиляция бинарника

Бинарник компилируется из `main.swift` **вместе с вшитыми исходниками SwiftMath** (см. раздел 23). В zsh:

```bash
swiftmath_sources=(SwiftMath/**/*.swift)
xcrun swiftc main.swift "${swiftmath_sources[@]}" -o Jot.app/Contents/MacOS/GlassPanel
```

Проще использовать `./rebuild.sh` — он делает это плюс копирует шрифты SwiftMath в Resources.

### 3.2. Пересборка с новой иконкой

```bash
# Если есть готовый .icns (например из IconPicker.app):
./rebuild_with_icon.sh /path/to/icon.icns

# Если нужно пересобрать из icon.png с цветом фона (по умолчанию #000F18):
./rebuild.sh
./rebuild.sh "#1A1A2E"  # другой цвет
```

Оба скрипта делают: нормализацию иконки → компиляция → `xattr -rc` → `codesign --force --deep --sign -` → `touch`.

**Почему их два:**
- `rebuild_with_icon.sh` — принимает готовый `.icns`, применяет как есть. Используется после экспорта из `IconPicker.app`.
- `rebuild.sh` — берёт `icon.png` из корня проекта, сам делает composite с цветом через Pillow, генерирует iconset и собирает. Удобен для смены цвета фона без открытия UI.

### 3.3. Важно о подписи

После любой модификации файлов в бандле (включая иконку) нужно переподписать:

```bash
xattr -rc Jot.app
codesign --force --deep --sign - Jot.app
```

`xattr -rc` обязателен перед codesign — иначе codesign падает с ошибкой "resource fork, Finder information, or similar detritus not allowed".

---

## 4. Архитектура приложения

Три основных уровня:

### 4.1. `PanelSettings`

Единый state-объект. Хранит все визуальные настройки, сериализует в `UserDefaults`, вычисляет производные цвета.

**Ключ хранения:** `Jot.settings`  
**Legacy ключ:** `GlassPanel.settings` (автоматически мигрирует при первом запуске)

**Важно:** При смене `CFBundleIdentifier` (как было при переходе с `com.glasspanel.GlassPanel` на `com.jot.Jot`) macOS начинает использовать другой `.plist` файл для UserDefaults. Это сбросило все пользовательские настройки. **Больше не менять `CFBundleIdentifier`.**

### 4.2. `GlassEditorView`

Основная view: glass-фон, слои, редактор, статус, wrap guides.

### 4.3. `AppDelegate`

Окно, меню, open/save, rainbow timer, привязка state.

---

## 5. Как устроен визуальный стек

Внутри `GlassEditorView`:

1. `NSGlassEffectContainerView`
2. `NSGlassEffectView`
3. `contentHost` (NSView)
4. `supplementalBlurView` (NSVisualEffectView, скрыт — наследие)
5. CALayer-слои (снизу вверх): `blurLayer`, `fillLayer`, `colorLayer`, `dimLayer`
6. `borderLayer` (CAShapeLayer)
7. `sheenLayer` (CAGradientLayer)
8. `hitShield` (HitTestShieldView)
9. `editorScrollView` (добавлен после hitShield — поэтому находится поверх него)
10. `fileStatusStack` (статус файла, верхний правый угол)

---

## 6. Двухслойный редактор текста

### 6.1. Зачем два слоя

Прямая перекраска рабочего `NSTextView` при rainbow-анимации вызывала мерцание, паразитные цвета, нестабильность выделения. Решение — разделить на два view:

- **`editorTextView`** (`EditorTextView: NSTextView`): редактируемый, прозрачный фон, белый полупрозрачный текст, принимает весь input.
- **`backdropTextView`** (`NSTextView`): не редактируемый, не selectable, расположен позади, показывает насыщенный цветной текст.

Вместе дают: белый текст с цветным подтоном — без мерцания при вводе.

### 6.2. Синхронизация

В `textDidChange`: `backdropTextView.string = editorTextView.string` → `syncEditorLayout()`.

Любое внешнее изменение текста должно проходить через `setText(_:)` — иначе два слоя расходятся.

### 6.3. Горячие клавиши по keyCode

`EditorTextView.performKeyEquivalent` реализован по физическим `keyCode` (A=0, Z=6, X=7, C=8, V=9), не по символам — это специально для корректной работы на неанглийских раскладках.

### 6.4. Двойной перезапуск blink timer

`EditorTextView.becomeFirstResponder` вызывает `updateInsertionPointStateAndRestartTimer(true)` дважды: один раз синхронно, второй раз в следующем runloop через `DispatchQueue.main.async`. Это нужно для корректного старта blink timer когда `becomeFirstResponder` вызывается до того как окно полностью установило key state (например, сразу после закрытия sheet).

---

## 7. Решённый баг: курсор не мигает после open/save

### Симптом (был)
После открытия или сохранения файла через sheet-панель курсор переставал мигать.

### Корневая причина
`applyAnimatedColorUpdate` (вызывается 30 раз/сек из rainbow timer) вызывал `updateFileStatusAppearance`, которая делала `needsLayout = true` на `GlassEditorView`. Это запускало `layout()` → `syncEditorLayout()` → `textContainer.containerSize = ...` + `ensureLayout(for:)` — инвалидацию текстового layout 30 раз в секунду. Инвалидация убивала blink timer.

**Это происходило только при включённом Rainbow Mode** (без него timer 30fps не работал).

### Исправление в коде

В `applyAnimatedColorUpdate` убран вызов `updateFileStatusAppearance`. Вместо него — прямое обновление только цветов:

```swift
func applyAnimatedColorUpdate(_ updatedSettings: PanelSettings, refreshEditorTint: Bool) {
    colorLayer.backgroundColor = updatedSettings.accentColor.cgColor
    applyBackdropTextColor(using: updatedSettings)
    wrapGuideView.guideColor = ...
    // НЕ вызываем updateFileStatusAppearance — это убивало blink timer
    fileIndicatorField.textColor = updatedSettings.documentIndicatorColor
    fileNameField.textColor = updatedSettings.statusTextColor
}
```

### Восстановление фокуса после sheet

Для корректного восстановления каретки после закрытия NSOpenPanel/NSSavePanel:

1. В completion block sheet устанавливается флаг `pendingFocusRestore = true`.
2. `windowDidBecomeKey` (если sheet вызвал didBecomeKey у родительского окна): сбрасывает флаг, делает `makeFirstResponder(nil)`, затем async → `focusEditor()`.
3. `scheduleFocusFallback()`: запасной путь на случай если `windowDidBecomeKey` не сработал — через 0.25s делает то же самое. Guard по `pendingFocusRestore` гарантирует однократное выполнение.

---

## 8. Wrap guides

### Зачем

Если включён Word Wrap, слева от перенесённых строк рисуются вертикальные маркеры (не line numbers — маркеры длины переноса).

### Калиброванные значения

Пользователь вручную подобрал значения wrap guides. UI настройки был удалён. Значения захардкожены в `normalizeFixedSettings()`:

```swift
settings.wrapGuideXOffset    = -10.37291937635512
settings.wrapGuideThickness  = 3.197090105162524
settings.wrapGuideTopTrim    = 8.003953657818043
settings.wrapGuideBottomTrim = 2.254072375033705
settings.wrapGuideOpacity    = 0.3048133243984811
settings.wrapGuideRounded    = true
```

Эти значения нельзя случайно сбросить — они всегда применяются при старте, поверх UserDefaults.

### Важный подводный камень

Если `editorTextView` пересоздаётся, нужно обязательно перепривязать:

```swift
wrapGuideView.textView = editorTextView
```

---

## 9. Rainbow Mode и Dock-иконка

### Rainbow в окне приложения

Timer 30fps меняет `settings.rainbowHue`, обновляет `colorLayer`, `backdropTextView`, wrap guides, file status (только цвета, без layout!), hue slider.

### Rainbow в Dock-иконке

При включённом Rainbow Mode иконка в Dock анимируется в том же ритме что и окно.

**Как работает (~5 fps, каждые 6 тиков):**

1. Базой служит `AppIcon.icns` из бандла (загружается один раз в `baseIconForDock`).
2. Создаётся `NSImage(size: 512×512)`:
   - Контент рисуется в 80% от размера, центрирован (паддинг 10% с каждой стороны — соответствует системным пропорциям Dock-иконок).
   - Clip path: скруглённый прямоугольник 22.5% радиус — macOS squircle-форма.
   - Рисуется base icon (`.sourceOver`).
   - Поверх — цвет текущего hue через `.color` blend mode, alpha=0.30.
3. Устанавливается как `NSApp.applicationIconImage`.

**Важно:** `.color` blend mode при `needsLayout`-вызовах мог создавать проблемы ранее. Текущая реализация стабильна.

**При отключении Rainbow:** `NSApp.applicationIconImage = nil` — Dock возвращается к системному рендерингу бандла.

**Почему НЕ устанавливается `NSApp.applicationIconImage` при старте:** Явная установка bypasses системный рендеринг (squircle clip, drop shadow). Иконка из бандла читается системой корректно — не надо вмешиваться.

---

## 10. Иконка приложения

### Текущая иконка

- Источник: `icon.png` (1024×1024 RGBA, стеклянная панель, прозрачные углы)
- Цвет фона: `#000F18` (очень тёмный сине-чёрный)
- Бандл содержит `AppIcon.icns` — composite из icon.png + фон, полностью непрозрачный
- Также в бандле: `BaseIcon.png` = оригинальный icon.png (используется для Dock-анимации)

### Почему нужен непрозрачный фон

Иконка — стеклянная панель с прозрачными углами. В Finder (белый фон) прозрачные пиксели показываются как белые → иконка не видна. Запечённый тёмный фон даёт одинаковый вид везде. Dock рендерит иконку из бандла через системный пайплайн (squircle clip + тень) — выглядит корректно.

### Важное о CFBundleIconName

У Jot нет `Assets.car` (нет полного Xcode). `CFBundleIconName` в Info.plist отсутствует намеренно — только `CFBundleIconFile`. Для standalone .icns без asset catalog это корректно. **Не добавлять `CFBundleIconName` без создания соответствующего `.car` файла.**

### Формат иконки macOS 11+

- Canvas: 1024×1024 px
- Прозрачные углы допустимы (macOS сам применяет squircle clip)
- Все 10 размеров: 16, 32, 128, 256, 512 × @1x и @2x
- iconutil создаёт `.icns` из папки `AppIcon.iconset`

---

## 11. IconPicker.app — утилита создания иконок

Находится в `IconPicker.app/` (рядом с `Jot.app/`).  
Исходник: `icon_picker/main.swift`.

### Что умеет

1. **Открыть PNG** — любой PNG-файл иконки
2. **Подобрать цвет фона** — preview с точным squircle-клиппингом (22.5% radius, continuous curve) как в macOS
3. **Скопировать HEX** — для использования в rebuild.sh
4. **Сохранить .icns** — генерирует все 10 размеров через Pillow + iconutil

### Workflow

```
IconPicker.app
→ Открыть PNG → выбрать цвет → Сохранить .icns → /путь/к/icon.icns
→ ./rebuild_with_icon.sh /путь/к/icon.icns
→ Jot.app пересобран с новой иконкой
```

### Известная особенность PATH

GUI приложения не наследуют shell PATH, поэтому Homebrew's `python3` не находится по умолчанию. IconPicker явно добавляет `/opt/homebrew/bin:/usr/local/bin` в PATH subprocess'а. Требования: `python3` + `Pillow` (`pip3 install Pillow`).

### Пересборка IconPicker

```bash
xcrun swiftc icon_picker/main.swift -o IconPicker.app/Contents/MacOS/IconPicker
codesign --force --sign - IconPicker.app
```

---

## 12. Настройки приложения

### UserDefaults

Сохраняются под ключом `Jot.settings` в файле `~/Library/Preferences/com.jot.Jot.plist`.

При первом запуске после миграции: код проверяет сначала `Jot.settings`, при отсутствии — `GlassPanel.settings` (старый ключ).

**Критически важно:** Смена `CFBundleIdentifier` меняет файл `.plist`. Не менять идентификатор — это сбросит все настройки пользователя.

### Фиксированные настройки (normalizeFixedSettings)

Применяются при каждом старте поверх UserDefaults:

```swift
glassStyle           = .clear
cornerRadius         = 30.0
tintStrength         = 0.0
warmth               = 0.0
fillOpacity          = 0.0
borderOpacity        = 0.05
sheenOpacity         = 0.01
shadowOpacity        = 0.0
shadowBlur           = 0.0
blurStrength         = 0.0
menuSliderOffset     = 25.0
documentIndicatorStyle = .star
wrapGuideXOffset     = -10.37291937635512
wrapGuideThickness   = 3.197090105162524
wrapGuideTopTrim     = 8.003953657818043
wrapGuideBottomTrim  = 2.254072375033705
wrapGuideOpacity     = 0.3048133243984811
wrapGuideRounded     = true
```

### Настраиваемые пользователем

Через меню Appearance: `darkeningOpacity`, `colorStrength`, `rainbowHue`, `rainbowSpeed`, `textColorStrength`, `alwaysOnTop`, `rainbowEnabled`.  
Через меню Format: `editorFontSize`, `wordWrap`, `showWrapGuides`.

---

## 13. Меню приложения

- **App**: Quit Jot
- **File**: Open… (Cmd+O), Save (Cmd+S), Save As… (Shift+Cmd+S)
- **Format**: Font Size (slider), Word Wrap, Wrapped Line Guides (disabled если Word Wrap выкл)
- **Appearance**: Always on Top, Rainbow Mode, Darkening, Color Strength, Hue, Rainbow Speed, Text Opacity

Слайдеры реализованы через `SliderMenuItemView` с фиксированной шириной 220px и переопределёнными `intrinsicContentSize`/`fittingSize`/`setFrameSize` — иначе NSMenuItem нестабильно меняет ширину.

---

## 14. Статус файла и индикатор несохранённости

Правый верхний угол: `fileStatusStack` с `fileIndicatorField` (символ `✶`) и `fileNameField`.

- Если файл не открыт/сохранён — стек скрыт.
- Если есть несохранённые изменения — показывается `✶` (стиль `.star`, захардкожен в `normalizeFixedSettings`).

**Регрессия которая была:** После удаления `rebuildWindowAfterOpenOrSave` имя файла перестало обновляться при открытии, потому что `markDocumentEdited(false)` имеет guard `isDocumentEdited != edited` и пропускал `setDocumentPresentation` если документ уже не был отредактирован. Исправлено: `openDocument(at:)` теперь вызывает `setDocumentPresentation` напрямую.

---

## 15. Traffic lights

Кнопки (close/minimize/zoom) **позиционирует сам AppKit**. Чтобы они сидели ниже (большое скругление угла, radius 30, иначе кнопки некрасиво близко к закруглению), титлбар сделан выше через прозрачный titlebar-accessory высотой `TitleBarLayout.titlebarHeight` (44) в `installTitlebarSpacer(in:)`.

### Почему так, а не ручной сдвиг

Раньше кнопки двигались вручную через `setFrameOrigin`. Это ломало hover: символы (×/−/+) рисует родительский `NSThemeFrame` по своей tracking-зоне, которая оставалась на дефолтном месте → наведение не попадало, символы мерцали. Поднятие титлбара через accessory заставляет AppKit самому опустить кнопки **вместе с tracking-зоной** → hover работает.

`positionTrafficLights()` теперь не двигает кнопки, а только дёргает `editorView.needsLayout` (статус-блок справа сверху следует за фактической позицией кнопок).

`titleBarMetrics()` читает **фактический** фрейм close-кнопки (`buttonSuperview.convert(...)`), поэтому позиция статуса и верхний отступ редактора подстраиваются автоматически под то, куда AppKit поставил кнопки.

### Тонкая настройка

Горизонтальный отступ кнопок задаёт AppKit (публично не меняется til-в-пиксель). Вертикаль регулируется `titlebarHeight`. Если кнопки сидят слишком высоко/низко — менять только эту константу.

---

## 16. Работа с файлами

### Открытие и сохранение

- Из Finder: `application(_:openFiles:)` → `openDocument(at:)`
- File → Open…: `NSOpenPanel.beginSheetModal` → completion → `openDocument(at:)`
- File → Save: прямой вызов `saveEditorText(to:)` если есть `currentFileURL`
- File → Save As…: `NSSavePanel.beginSheetModal` → completion → `saveEditorText(to:)`

### Директория по умолчанию

Папка текущего файла, или рабочий стол если файл не открыт.

### Если файл удалён после сохранения

Следующий Save пересоздаёт файл по старому пути. Это осознанное решение.

---

## 17. Подводные камни AppKit

- **NSTextView + live color update**: слишком частое изменение `typingAttributes`, `textStorage`, `textColor` → мерцание. Именно поэтому `applyAnimatedColorUpdate` обновляет только `backdropTextView`, не `editorTextView`.
- **NSMenuItem.view + слайдеры**: без фиксированных размеров через `SliderMenuItemView` слайдеры нестабильно меняют ширину.
- **fullSizeContentView**: кнопки нужно позиционировать вручную.
- **Два текстовых слоя**: любое изменение текста вне `textDidChange` должно проходить через `setText(_:)`.
- **needsLayout = true в анимационном пути**: вызов из 30fps timer приводит к инвалидации text layout и убивает blink timer курсора.
- **NSApp.applicationIconImage**: явная установка при старте bypasses системный рендеринг иконки (squircle, drop shadow). Не устанавливать без нужды.
- **xattr и codesign**: xattr от NSWorkspace.setIcon или Finder ломают codesign. Всегда `xattr -rc` перед подписью.
- **CFBundleIdentifier и UserDefaults**: смена идентификатора = смена файла .plist = потеря всех настроек.

---

## 18. Текущие известные проблемы

### Отсутствие Assets.car

Для правильного отображения иконки во всех контекстах macOS 11+ рекомендует `Assets.car` (скомпилированный asset catalog). Без полного Xcode `actool` недоступен — создать `.car` невозможно. Текущий workaround: непрозрачный `.icns` с запечённым фоном. В Dock и Finder иконка выглядит корректно.

### clearCustomFinderIcon()

При старте вызывается `NSWorkspace.setIcon(nil, forFile: bundlePath)` — очищает возможные xattr от предыдущих версий приложения, которые ставили кастомную иконку. Можно убрать после нескольких версий.

---

## 19. Что делать следующему агенту в первую очередь

1. Прочитать раздел 7 (баг с курсором) — понять почему `needsLayout = true` в 30fps пути убивает blink timer.
2. Прочитать раздел 6.4 (двойной перезапуск blink timer) — понять механизм восстановления каретки.
3. НЕ трогать `applyAnimatedColorUpdate` без понимания последствий для blink timer.
4. НЕ менять `CFBundleIdentifier`.
5. НЕ добавлять `NSApp.applicationIconImage` при старте без явной нужды.
6. НЕ менять фиксированные значения wrap guides — они подобраны вручную.

---

## 20. Краткая карта кода

| Класс/структура | Назначение |
|---|---|
| `PanelSettings` | State, UserDefaults, вычисляемые цвета |
| `PanelWindow` | `canBecomeKey/Main = true` |
| `FlippedContentView` | Flipped координаты для text container |
| `WrapGuideView` | Рисует маркеры переноса строк |
| `HitTestShieldView` | Позволяет таскать окно за пустые зоны |
| `EditorTextView` | Хоткеи по keyCode + двойной blink restart |
| `SliderMenuItemView` | Стабильные слайдеры в NSMenu |
| `GlassEditorView` | Весь UI: glass, layers, editor, status, guides |
| `AppDelegate` | Окно, меню, open/save, rainbow timer, Dock icon |

---

## 21. Текущие пользовательские предпочтения (зафиксированы)

- `cornerRadius = 30` — скругление панели
- `documentIndicatorStyle = .star` — символ несохранённости `✶`
- `bgColor для иконки = #000F18` — тёмно-синий фон
- Wrap guides: смотри раздел 8, все значения в `normalizeFixedSettings()`
- Без screen recording permission
- Без приватных API
- Rainbow Dock icon: squircle clip + `.color` blend, alpha=0.30, saturation=0.65, 80% scale

---

## 22. История ключевых решений

| Решение | Причина |
|---|---|
| Два текстовых слоя | Мерцание при прямой перекраске editorTextView в rainbow |
| Горячие клавиши по keyCode | Баги на неанглийских раскладках |
| SliderMenuItemView с фиксированными размерами | NSMenuItem нестабильно менял ширину слайдеров |
| Wrap guides захардкожены в normalizeFixedSettings | UI настройки удалён, значения должны сохраняться |
| Удалён rebuildWindowAfterOpenOrSave | Не помогал с blink timer, добавлял сложность |
| Фикс: убрать updateFileStatusAppearance из 30fps пути | needsLayout → syncEditorLayout убивал blink timer |
| Двойной updateInsertionPointStateAndRestartTimer | Первый вызов до fully-settled window state; второй надёжнее |
| Непрозрачный icns (#000F18 фон) | Прозрачная иконка невидима на белом фоне Finder |
| NSApp.applicationIconImage не устанавливается при старте | Обход системного рендеринга (squircle, shadow) |
| Dock icon: 80% scale + squircle clip | Системный рендеринг бандла имеет неявный паддинг/масштаб |

---

## 23. SwiftMath: рендеринг LaTeX-формул

### 23.1. Что это и зачем

[SwiftMath](https://github.com/mgriebling/SwiftMath) — нативная библиотека рендеринга LaTeX-математики через CoreText (порт iosMath). Выбрана вместо KaTeX/WebKit потому что даёт **синхронный** рендер прямо в `NSImage`, что нужно для инлайн-вставки формул в текст без async-снимков webview.

Инлайн-формулы реализованы (см. 23.6): ввод `$$`, живой предпросмотр в стеклянной панели, сворачивание в отрендеренную формулу, повторное редактирование по клику.

### 23.2. Как вшита

- Исходники (28 .swift файлов) лежат в `SwiftMath/` — компилируются вместе с `main.swift`.
- `SwiftMath/BundleModuleShim.swift` — определяет `Bundle.module` → `Bundle.main`. SwiftMath написан как SPM-пакет и грузит шрифты через `Bundle.module`, которого нет при сборке через `swiftc`. Shim перенаправляет на main bundle.
- Шрифт-мастер: `SwiftMath/mathFonts.bundle/` — только дефолтный `latinmodern-math.otf` + `.plist` (из 12 доступных шрифтов взят один, чтобы не тащить 7 МБ). Билд-скрипты копируют его в `Jot.app/Contents/Resources/mathFonts.bundle`.

### 23.3. Минимальный пример рендера

```swift
let mathImage = MTMathImage(latex: "x = \\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}",
                            fontSize: 30, textColor: .white, labelMode: .display)
let (error, image) = mathImage.asImage()   // image: NSImage?
```

### 23.4. Подводные камни

- Минимальная версия macOS у SwiftMath — 12.0 (в `Info.plist` сейчас стоит 11.0; для распространения учесть).
- Если понадобится другой шрифт — добавить его `.otf` + `.plist` в `SwiftMath/mathFonts.bundle/`.
- Предупреждения о deprecated `CTFontManagerRegisterGraphicsFont` (macOS 15) — не критичны, работают.
- Шрифт грузится лениво и кешируется (`BundleManager`). Первый рендер чуть медленнее.

### 23.5. Лицензия

SwiftMath — MIT (см. `SwiftMath/LICENSE`). Шрифт latinmodern-math — OFL (см. `SwiftMath/mathFonts.bundle/OFL.txt`).

### 23.6. UX инлайн-формул

#### Сценарий (модель парных разделителей `$$…$$`)

1. Ввод `$$` → автоматически дописывается закрывающий `$$`, каретка ставится посередине (`$$|$$`). Снизу появляется стеклянная панель (`MathPreviewView`) с живым предпросмотром.
2. Печать LaTeX между разделителями — исходник `$$latex$$` подсвечивается (тёмный фон + серый шрифт), предпросмотр обновляется на каждый ввод.
3. Enter / стрелка-вправо в конце / клик в стороне → формула сворачивается в `MathAttachment` (картинка inline).
4. Клик или стрелка на свёрнутую формулу → разворачивается обратно в `$$latex$$` + предпросмотр. Клик внутрь сырого `$$…$$` (например, после невалидного коммита) тоже открывает редактирование.
5. Пустая формула: Backspace или стрелка-влево у начала удаляет весь `$$$$` и выходит.

#### Ключевые компоненты

- `MathEditingHost` (протокол) — `EditorTextView` дёргает `mathCommit`/`mathDeleteBackwardAtStart` из `insertNewline`/`moveRight`/`moveLeft`/`deleteBackward`.
- `MathAttachment: NSTextAttachment` — хранит `latex`, держит картинку, центрирует по вертикали через `attachmentBounds`.
- `MathPreviewView` — стеклянная панель. Картинка кладётся в `glass.contentView` (иначе она под стеклом и размывается), padding 22.
- `MathRenderer.renderImage(latex:fontSize:color:)` — LaTeX → NSImage.

#### Модель состояния

- `mathEditRange: NSRange?` — полный диапазон `$$…$$` (включая оба разделителя). latex = `[location+2, length-4]`.
- `pendingAutoCloseAt: Int?` — где надо авто-дописать `$$` (выставляется в `shouldChangeTextIn` при наборе второго `$`).
- `isProcessingMath` — guard от реентрантности при программных правках.
- Диапазон поддерживается в `shouldChangeTextIn`; детект/авто-закрытие/валидация — в `handleMathAfterTextChange`; переходы — в `textViewDidChangeSelection`.

#### Синхронизация двух слоёв (важно!)

`syncBackdrop()` копирует **attributed** строку фронта в backdrop (а не `.string`), включая attachment'ы формул. Это держит цветной задний слой выровненным с белым передним — формулы есть в обоих слоях, картинки совпадают по позиции. Раньше backdrop получал `.string` (узкий `U+FFFC`) → текст за формулами съезжал.

#### Round-trip

- `text` getter → `serializedText()`: attachment'ы → `$$latex$$`. Файл — стандартный текст с display-math.
- `setText` → `attributedStringRenderingFormulas`: при загрузке `$$…$$` → attachment'ы (рендерятся сразу).

#### Известные ограничения

- При смене размера шрифта уже свёрнутые формулы не перерисовываются (остаются в старом размере).
- Подсветка исходника во время редактирования временно убирается при изменении настроек оформления (восстанавливается на следующий ввод).
- SwiftMath грузит шрифт лениво при первом рендере — первая формула чуть медленнее.

#### Не сделано (отложено)

- Bug 7: панель предпросмотра как «облачко из комикса» с острым углом-указателем на формулу.

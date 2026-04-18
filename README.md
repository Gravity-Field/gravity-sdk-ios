# 📦 GravitySDK for iOS

`GravitySDK` — это мощный инструмент для интеграции персонализированного контента, отслеживания взаимодействия пользователей и отображения кампаний в мобильных iOS-приложениях. Он позволяет получать контент по шаблонам, отслеживать события и отображать контент в различных форматах (модальное окно, полноэкранный режим, bottom sheet).

## 📚 Оглавление

- [✨ Возможности](#возможности)
- [🚀 Установка](#установка)
- [⚙️ Инициализация](#инициализация)
- [🔧 Дополнительные параметры initialize](#дополнительные-параметры-initialize)
- [🎨 ProductViewBuilder — кастомизация отображения продуктов](#productviewbuilder--кастомизация-отображения-продуктов)
- [🧑 Пользователь и настройки](#пользователь-и-настройки)
- [📄 Отслеживание и события](#отслеживание-и-события)
- [📈 Взаимодействие](#взаимодействие)
- [🧩 Получение контента](#получение-контента)
- [🖼️ Отображение контента](#отображение-контента)
- [❗ Обработка ошибок](#обработка-ошибок)

## Возможности

- Инициализация SDK с ключом API и параметрами секции
- Настройка контента и прокси
- Отслеживание посещений страниц и пользовательских событий
- Получение контента по шаблону
- Отображение контента в:
    - Модальном окне
    - Bottom sheet
    - Полноэкранном режиме
    - Snackbar
    - Bottom sheet с рядом товаров
- Отправка взаимодействий с контентом и продуктами

## Установка

Добавь зависимость через Swift Package Manager:

```
https://github.com/Gravity-Field/gravity-sdk-ios.git
```

Или в `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Gravity-Field/gravity-sdk-ios.git", from: "0.0.9")
]
```

## Инициализация

Для работы SDK необходимо провести базовую инициализацию, передав параметры `apiKey` и `section`. Их можно найти в личном кабинете.

```swift
GravitySDK.initialize(
    apiKey: "your-api-key",
    section: "your-section-id"
)
```

## Дополнительные параметры initialize

```swift
GravitySDK.initialize(
    apiKey: String,
    section: String,
    gravityEventCallback: GravityEventCallback? = nil,
    productViewBuilder: ProductViewBuilder? = nil,
    productFilter: ProductFilter? = nil,
    logLevel: LogLevel = .error,
)
```

- `productViewBuilder` — кастомная отрисовка карточек продуктов
- `gravityEventCallback` — колбэк, вызываемый при трекинге событий
- `productFilter` — фильтр продуктов
- `logLevel` — уровень логирования SDK. По умолчанию `.error` — видны только ошибки

## ProductViewBuilder — кастомизация отображения продуктов

ProductViewBuilder — это интерфейс, предназначенный для кастомной отрисовки карточек продуктов в рамках кампаний. Он предоставляет гибкость, позволяя разработчику контролировать внешний вид товаров, интегрированных в кампанию, чтобы они соответствовали стилю приложения.

**Зачем это нужно?**

Часть кампаний содержит продукты (например, рекомендованные товары, акции, предложения). Чтобы эти карточки визуально вписывались в интерфейс приложения, необходимо передать в SDK свою реализацию ProductViewBuilder.

Если не указать productViewBuilder, продукты не будут отображены.

## Пользователь и настройки

```swift
GravitySDK.instance.setUser(userId: "user-id", sessionId: "session-id")

GravitySDK.instance.setOptions(
    options: Options(...),
    contentSettings: ContentSettings(...),
    proxyUrl: url,
)
```

## Отслеживание и события

```swift
GravitySDK.instance.trackView(
    pageContext: PageContext(...),
    viewController: viewController,
)

GravitySDK.instance.triggerEvent(
    events: [TriggerEvent(...)],
    pageContext: PageContext(...),
    viewController: viewController,
)
```

## Взаимодействие

```swift
GravitySDK.instance.sendContentEngagement(engagement: ContentImpressionEngagement(...))
GravitySDK.instance.sendProductEngagement(engagement: ProductClickEngagement(...))
```

## Получение контента

```swift
let response = await GravitySDK.instance.getContentBySelector(
    selector: "selector",
    pageContext: PageContext(...),
)
```

## Отображение контента

Отображение контента происходит автоматически после вызова одного из методов: `trackView`
или `triggerEvent`

## Обработка ошибок

Если любой публичный метод SDK вызван до `GravitySDK.initialize(...)`, вызов безопасно игнорируется:
в лог пишется сообщение об ошибке, а методы, возвращающие значение, возвращают `nil`

Проверить состояние инициализации можно так:

```swift
if GravitySDK.isInitialized {
    // SDK готов к работе
}
```

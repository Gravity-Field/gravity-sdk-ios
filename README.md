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

## Подготовка in-app перед показом

`initialize` принимает необязательный `inAppPreparation`. Обработчик получает контент и кампанию, асинхронно проверяет товары и возвращает контент для показа либо `nil`, чтобы пропустить этот in-app и перейти к следующей кампании.

```swift
GravitySDK.initialize(
    apiKey: "your-api-key",
    section: "your-section-id",
    productViewBuilder: reviewIntegration.productViewBuilder,
    inAppPreparation: reviewIntegration.preparation()
)
```

[Пример ReviewPromptIntegration](Example/GravitySDKDemo/GravitySDKDemo/ReviewPromptIntegration.swift) включает интерфейс клиентского API eligibility, карточку с кнопкой «Оставить отзыв» и обновление локального статуса через `didSubmitReview(sku:)` после успешной отправки отзыва. `onOpenReview` — маршрутизация приложения: клиент закрывает текущий sheet и открывает свой экран отзыва. Пример не включён по умолчанию: для него нужен API клиента.

Обработчик можно написать напрямую:

В примере задайте `selector` кампании отзывов и `fallbackProductViewBuilder` для остальных кампаний. Если у кампании нет selector, ограничьте обработку по `campaign.payload.first?.campaignId`.

```swift
let preparation = InAppPreparation(timeout: 5) { content, campaign in
    guard campaign.selector == "purchase-reviews" else { return content }
    let skus = content.products?.slots?.compactMap { $0.item["sku"] as? String } ?? []
    guard !skus.isEmpty else { return nil }
    let eligible = try await reviewAPI.eligibleSkus(Array(Set(skus)))
    return content.filteringProducts { slot in
        guard let sku = slot.item["sku"] as? String else { return false }
        return eligible.contains(sku)
    }
}
```

Порядок: `/choose` → существующий синхронный `productFilter` → content-loaded tracking → задержка кампании → `inAppPreparation` → повторная проверка возможности показа → UI и impression-события. Обработчик применяется к автоматическому показу после `trackView`/`triggerEvent`, а также при `open_step`. Получение через `getContentBy*` и inline-виджеты сохраняют прежнее поведение.

- Без обработчика нет ожидания API. Для других кампаний верните исходный `content`.
- `filteringProducts` сохраняет исходные слоты, порядок, tracking-данные и метаданные; пустой результат возвращает `nil`. Пустые блоки в других кампаниях не запрещены.
- Таймаут по умолчанию — 5 секунд. Ошибка, таймаут или некорректный timeout (не положительный, не конечный либо больше часа) пропускают in-app. Используйте отменяемый async API; не блокируйте поток.
- После ожидания проверяются экран, presentation lock и ревизия пользователя. `setUser` и `lockPresentation` инвалидируют ожидающий показ, даже если затем восстановлено прежнее состояние. При навигации внутри одного контроллера блокируйте показ через `lockPresentation`. После разблокировки нужен новый view/trigger.
- Пропущенный in-app не отправляет impression/visible impression; content-loaded сохраняет семантику загрузки. Удалённые слоты не монтируются. В своём builder отправляйте клик через `sendProductEngagement`.
- Используйте recently purchased без fallback на непокупавшиеся товары. Правила доставки/отмены/возврата проверяет API eligibility. Запрашивайте кандидатов с запасом: SDK не восполняет удалённые товары.
- Перед запуском проверьте пользователя в `/choose` (отдельное исправление EGO-246). Клиентский статус отзывов должен принадлежать текущему аккаунту.
